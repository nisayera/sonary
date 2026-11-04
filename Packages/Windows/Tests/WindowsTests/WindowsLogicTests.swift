import Foundation
import CoreGraphics
import Testing
@testable import Windows

struct WindowLayoutTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let current = CGRect(x: 10, y: 10, width: 400, height: 300)

    @Test func halves() {
        #expect(layoutFrame(.leftHalf, visible: visible, current: current) == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(layoutFrame(.rightHalf, visible: visible, current: current) == CGRect(x: 500, y: 0, width: 500, height: 800))
        #expect(layoutFrame(.topHalf, visible: visible, current: current) == CGRect(x: 0, y: 400, width: 1000, height: 400))
    }

    @Test func quartersAndThirds() {
        #expect(layoutFrame(.topRight, visible: visible, current: current) == CGRect(x: 500, y: 400, width: 500, height: 400))
        #expect(layoutFrame(.centerThird, visible: CGRect(x: 0, y: 0, width: 900, height: 600), current: current)
            == CGRect(x: 300, y: 0, width: 300, height: 600))
    }

    @Test func maximizeFillsVisibleFrame() {
        let v = CGRect(x: 1440, y: 25, width: 1920, height: 1055)
        #expect(layoutFrame(.maximize, visible: v, current: current) == v)
    }

    @Test func centerKeepsSizeAndClamps() {
        #expect(layoutFrame(.center, visible: visible, current: current) == CGRect(x: 300, y: 250, width: 400, height: 300))
        let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        #expect(layoutFrame(.center, visible: visible, current: huge) == visible)
    }

    @Test func respectsScreenOffset() {
        let v = CGRect(x: 1920, y: 0, width: 1000, height: 800)
        #expect(layoutFrame(.leftHalf, visible: v, current: current).minX == 1920)
    }

    @Test func axConversionRoundTrips() {
        let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
        let ax = axRect(fromCocoa: cocoa, primaryScreenHeight: 1000)
        #expect(ax == CGRect(x: 100, y: 400, width: 300, height: 400))
        #expect(cocoaRect(fromAX: ax, primaryScreenHeight: 1000) == cocoa)
    }

    @Test func everyActionHasADistinctKey() {
        let codes = LayoutAction.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }
}

struct QuitGuardTests {
    @Test func firstPressIsSwallowed() {
        var guardian = QuitGuard()
        let r1 = guardian.shouldQuit(app: "a", at: 10)
        #expect(!r1)
    }

    @Test func secondPressInsideWindowQuits() {
        var guardian = QuitGuard(window: 1.5)
        _ = guardian.shouldQuit(app: "a", at: 10)
        let r2 = guardian.shouldQuit(app: "a", at: 11)
        #expect(r2)
    }

    @Test func slowSecondPressStartsOver() {
        var guardian = QuitGuard(window: 1.5)
        _ = guardian.shouldQuit(app: "a", at: 10)
        let r3 = guardian.shouldQuit(app: "a", at: 13)
        #expect(!r3)
        let r4 = guardian.shouldQuit(app: "a", at: 13.5)
        #expect(r4)
    }

    @Test func otherAppStartsOver() {
        var guardian = QuitGuard()
        _ = guardian.shouldQuit(app: "a", at: 10)
        let r5 = guardian.shouldQuit(app: "b", at: 10.5)
        #expect(!r5)
    }
}

struct WindowSwitcherTests {
    private func window(_ id: Int, _ pid: Int, _ app: String, _ title: String?,
                        layer: Int = 0, w: Double = 800, h: Double = 600) -> [String: Any] {
        var dict: [String: Any] = [
            "kCGWindowNumber": NSNumber(value: id), "kCGWindowOwnerPID": NSNumber(value: pid),
            "kCGWindowOwnerName": app, "kCGWindowLayer": layer,
            "kCGWindowBounds": ["Width": NSNumber(value: w), "Height": NSNumber(value: h)],
        ]
        if let title { dict["kCGWindowName"] = title }
        return dict
    }

    @Test func keepsRealWindowsInOrder() {
        let entries = switcherEntries(from: [window(1, 10, "Safari", "Start"), window(2, 11, "Mail", "Inbox")],
                                      excludingPID: 99)
        #expect(entries.map(\.appName) == ["Safari", "Mail"])
        #expect(entries.first?.label == "Safari — Start")
    }

    @Test func skipsMenuBarAndTinyWindows() {
        let entries = switcherEntries(from: [window(1, 10, "Bar", "x", layer: 25), window(2, 11, "Tiny", "x", w: 40, h: 20)],
                                      excludingPID: 99)
        #expect(entries.isEmpty)
    }

    @Test func skipsOurOwnWindows() {
        #expect(switcherEntries(from: [window(1, 99, "Sonary", "Panel")], excludingPID: 99).isEmpty)
    }

    @Test func untitledWindowShowsTheAppName() {
        let entries = switcherEntries(from: [window(1, 10, "Preview", nil)], excludingPID: 99)
        #expect(entries.first?.label == "Preview")
    }

    @Test func selectionWrapsBothWays() {
        #expect(nextIndex(from: 2, count: 3, forward: true) == 0)
        #expect(nextIndex(from: 0, count: 3, forward: false) == 2)
        #expect(nextIndex(from: 0, count: 0, forward: true) == 0)
    }

    @Test func searchMatchesAppAndTitle() {
        let entries = [WindowEntry(id: 1, pid: 1, appName: "Safari", title: "News"),
                       WindowEntry(id: 2, pid: 2, appName: "Mail", title: "Inbox")]
        #expect(filteredEntries(entries, query: "mail").map(\.id) == [2])
        #expect(filteredEntries(entries, query: "news").map(\.id) == [1])
        #expect(filteredEntries(entries, query: " ").count == 2)
    }
}

struct ProtectionTests {
    @Test func quitAndCloseAreArmedSeparately() {
        var guardian = QuitGuard()
        let result1 = guardian.shouldQuit(app: "a", key: .quit, at: 10)
        #expect(!result1)
        let result2 = guardian.shouldQuit(app: "a", key: .close, at: 10.2)
        #expect(!result2)
        let outcome1 = guardian.shouldQuit(app: "a", key: .close, at: 10.4)
        #expect(outcome1)
    }

    @Test func emptyListProtectsEveryApp() {
        #expect(isProtected(bundleID: "com.any.app", onlyApps: []))
    }

    @Test func aListProtectsOnlyItsApps() {
        #expect(isProtected(bundleID: "com.a", onlyApps: ["com.a"]))
        #expect(!isProtected(bundleID: "com.b", onlyApps: ["com.a"]))
    }
}

struct MoveBetweenScreensTests {
    private let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let right = CGRect(x: 1000, y: 0, width: 2000, height: 1000)

    @Test func wrapsThroughTheScreens() {
        let onLeft = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(nextScreen(after: onLeft, screens: [left, right]) == right)
        let onRight = CGRect(x: 1200, y: 100, width: 400, height: 300)
        #expect(nextScreen(after: onRight, screens: [left, right]) == left)
    }

    @Test func oneScreenHasNoNext() {
        #expect(nextScreen(after: CGRect(x: 0, y: 0, width: 10, height: 10), screens: [left]) == nil)
    }

    @Test func keepsTheRelativePlaceAndSize() {
        let frame = CGRect(x: 500, y: 400, width: 500, height: 400)
        let moved = movedFrame(frame, from: left, to: right)
        #expect(moved.minX == 2000)
        #expect(moved.width == 1000)
        #expect(moved.height == 500)
    }

    @Test func staysInsideTheTargetScreen() {
        let frame = CGRect(x: 900, y: 700, width: 400, height: 300)
        let moved = movedFrame(frame, from: left, to: right)
        #expect(moved.maxX <= right.maxX)
        #expect(moved.maxY <= right.maxY)
    }

    @Test func aWindowBiggerThanItsScreenIsNotGrownFurther() {
        let huge = CGRect(x: 0, y: 0, width: 4000, height: 4000)
        let moved = movedFrame(huge, from: left, to: right)
        #expect(moved.width <= right.width && moved.height <= right.height)
    }
}

struct QuitWhenLastWindowClosesTests {
    @Test func appThatLostItsLastWindowIsQuit() {
        #expect(appsWithNoWindowsLeft(previous: [1: 2, 2: 1], current: [1: 0, 2: 1]) == [1])
    }

    @Test func appWithoutWindowsBeforeIsLeftAlone() {
        #expect(appsWithNoWindowsLeft(previous: [1: 0], current: [1: 0]).isEmpty)
    }

    @Test func appThatDisappearedIsLeftAlone() {
        #expect(appsWithNoWindowsLeft(previous: [1: 3], current: [:]).isEmpty)
    }

    @Test func newAppsAreIgnored() {
        #expect(appsWithNoWindowsLeft(previous: [:], current: [5: 0]).isEmpty)
    }
}

struct EdgeSnappingTests {
    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func sidesGiveHalves() {
        #expect(edgeLayout(for: CGPoint(x: 2, y: 500), in: visible) == .leftHalf)
        #expect(edgeLayout(for: CGPoint(x: 1599, y: 500), in: visible) == .rightHalf)
    }

    @Test func topMaximizesAndBottomHalves() {
        #expect(edgeLayout(for: CGPoint(x: 800, y: 999), in: visible) == .maximize)
        #expect(edgeLayout(for: CGPoint(x: 800, y: 1), in: visible) == .bottomHalf)
    }

    @Test func cornersWinOverSides() {
        #expect(edgeLayout(for: CGPoint(x: 2, y: 995), in: visible) == .topLeft)
        #expect(edgeLayout(for: CGPoint(x: 1598, y: 995), in: visible) == .topRight)
        #expect(edgeLayout(for: CGPoint(x: 2, y: 5), in: visible) == .bottomLeft)
        #expect(edgeLayout(for: CGPoint(x: 1598, y: 5), in: visible) == .bottomRight)
    }

    @Test func themiddleSnapsNothing() {
        #expect(edgeLayout(for: CGPoint(x: 800, y: 500), in: visible) == nil)
    }

    @Test func offScreenSnapsNothing() {
        #expect(edgeLayout(for: CGPoint(x: -50, y: 500), in: visible) == nil)
        #expect(edgeLayout(for: CGPoint(x: 800, y: 2000), in: visible) == nil)
    }

    @Test func turnedOffByZeroThreshold() {
        #expect(edgeLayout(for: CGPoint(x: 0, y: 500), in: visible, threshold: 0) == nil)
    }
}

struct FocusFollowsMouseTests {
    private let windows: [(pid: Int32, frame: CGRect)] = [
        (pid: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 500)),
        (pid: 2, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
    ]

    @Test func frontWindowWins() {
        #expect(windowUnder(CGPoint(x: 100, y: 100), in: windows) == 1)
        #expect(windowUnder(CGPoint(x: 800, y: 800), in: windows) == 2)
        #expect(windowUnder(CGPoint(x: 2000, y: 2000), in: windows) == nil)
    }

    @Test func focusWaitsForTheDelay() {
        var state = FocusFollowState(delay: 0.3)
        #expect(state.pointer(over: 7, at: 10, focused: 1) == nil)
        #expect(state.pointer(over: 7, at: 10.1, focused: 1) == nil)
        #expect(state.pointer(over: 7, at: 10.4, focused: 1) == 7)
    }

    @Test func focusFiresOnlyOnce() {
        var state = FocusFollowState(delay: 0.3)
        _ = state.pointer(over: 7, at: 10, focused: 1)
        #expect(state.pointer(over: 7, at: 10.4, focused: 1) == 7)
        #expect(state.pointer(over: 7, at: 10.5, focused: 1) == nil)
    }

    @Test func movingAwayResetsTheWait() {
        var state = FocusFollowState(delay: 0.3)
        _ = state.pointer(over: 7, at: 10, focused: 1)
        _ = state.pointer(over: 8, at: 10.2, focused: 1)
        #expect(state.pointer(over: 7, at: 10.4, focused: 1) == nil)
    }

    @Test func theAppAlreadyInFrontIsLeftAlone() {
        var state = FocusFollowState(delay: 0)
        #expect(state.pointer(over: 1, at: 10, focused: 1) == nil)
        #expect(state.pointer(over: nil, at: 10, focused: 1) == nil)
    }
}
