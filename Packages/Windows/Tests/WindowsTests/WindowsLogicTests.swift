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

@Suite struct FillScreenTests {
    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 960)
    private let full = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func fillingTakesTheWholeScreenAndMaximizeDoesNot() {
        #expect(layoutFrame(.fillScreen, visible: visible, full: full, current: .zero) == full)
        #expect(layoutFrame(.maximize, visible: visible, full: full, current: .zero) == visible)
    }

    @Test func theThreeArgumentFormStillOnlyKnowsTheVisibleFrame() {
        #expect(layoutFrame(.fillScreen, visible: visible, current: .zero) == visible)
    }

    @Test func everyLayoutHasAKeyOfItsOwn() {
        let codes = LayoutAction.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count, "two layouts would fight over one shortcut")
        #expect(LayoutAction.fillScreen.shortcutLabel == "⌃⌥B")
    }
}

@Suite struct SpaceOrderTests {
    @Test func fixedIsTheOppositeOfRearranging() {
        #expect(spaceOrderIsFixed(rearrangesAutomatically: false))
        #expect(!spaceOrderIsFixed(rearrangesAutomatically: true))
    }
}

@Suite struct DockActionTests {
    private func entry(pid: Int32, number: UInt32, layer: Int = 0,
                       width: Double = 800, height: Double = 600, title: String = "Doc") -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid,
            kCGWindowNumber as String: number,
            kCGWindowLayer as String: layer,
            kCGWindowName as String: title,
            kCGWindowBounds as String: ["X": 10.0, "Y": 20.0, "Width": width, "Height": height],
        ]
    }

    @Test func keepsOnlyTheRealWindowsOfOneApp() {
        let info = [
            entry(pid: 1, number: 10),
            entry(pid: 2, number: 11),
            entry(pid: 1, number: 12, layer: 25),          // a panel or menu, not a window
            entry(pid: 1, number: 13, width: 20, height: 8), // too small to be a window
            entry(pid: 1, number: 14, title: ""),
        ]
        let windows = dockWindows(ofPID: 1, in: info)
        #expect(windows.map(\.id) == [10, 14])
        #expect(windows.first?.frame == CGRect(x: 10, y: 20, width: 800, height: 600))
        #expect(windows.last?.title.isEmpty == true, "a window with no name still counts")
    }

    @Test func cyclingWrapsAroundAndCopesWithOne() {
        let windows = [DockWindow(id: 1, title: "a", frame: .zero),
                       DockWindow(id: 2, title: "b", frame: .zero),
                       DockWindow(id: 3, title: "c", frame: .zero)]
        #expect(nextWindowToRaise(after: 1, in: windows)?.id == 2)
        #expect(nextWindowToRaise(after: 3, in: windows)?.id == 1)
        #expect(nextWindowToRaise(after: nil, in: windows)?.id == 1)
        #expect(nextWindowToRaise(after: 99, in: windows)?.id == 1, "a window that has gone starts over")
        #expect(nextWindowToRaise(after: 1, in: [windows[0]])?.id == 1)
        #expect(nextWindowToRaise(after: nil, in: []) == nil)
    }

    @Test func previewsWaitForThePointerToSettle() {
        var state = DockHoverState(delay: 0.4)
        #expect(state.pointer(over: 42, at: 0) == nil)
        #expect(state.pointer(over: 42, at: 0.2) == nil, "still too soon")
        #expect(state.pointer(over: 42, at: 0.45) == 42)
        #expect(state.pointer(over: 42, at: 0.5) == nil, "it has already opened")
    }

    @Test func movingToAnotherIconStartsTheWaitAgain() {
        var state = DockHoverState(delay: 0.4)
        #expect(state.pointer(over: 42, at: 0) == nil)
        #expect(state.pointer(over: 7, at: 0.39) == nil)
        #expect(state.pointer(over: 7, at: 0.5) == nil, "the clock restarted on the new icon")
        #expect(state.pointer(over: 7, at: 0.8) == 7)
        #expect(state.pointer(over: nil, at: 0.9) == nil)
    }
}

@Suite struct HoldGuardTests {
    @Test func holdingLongEnoughLetsItThrough() {
        var guardState = HoldGuard(duration: 0.6)
        let first = guardState.down(app: "a", key: .quit, at: 0)
        #expect(!first, "the first press only starts the clock")
        let early = guardState.down(app: "a", key: .quit, at: 0.3)
        #expect(!early)
        let late = guardState.down(app: "a", key: .quit, at: 0.7)
        #expect(late)
    }

    @Test func lettingGoCancels() {
        var guardState = HoldGuard(duration: 0.6)
        let first = guardState.down(app: "a", key: .quit, at: 0)
        #expect(!first)
        guardState.up()
        let afterRelease = guardState.down(app: "a", key: .quit, at: 0.7)
        #expect(!afterRelease, "the clock starts again after letting go")
        let held = guardState.down(app: "a", key: .quit, at: 1.4)
        #expect(held)
    }

    @Test func anotherAppOrKeyStartsOver() {
        var guardState = HoldGuard(duration: 0.6)
        let first = guardState.down(app: "a", key: .quit, at: 0)
        #expect(!first)
        let otherApp = guardState.down(app: "b", key: .quit, at: 0.7)
        #expect(!otherApp, "a different app is a different hold")
        let otherKey = guardState.down(app: "b", key: .close, at: 1.0)
        #expect(!otherKey, "and so is a different key")
    }

    @Test func progressGrowsAndStopsAtOne() {
        var guardState = HoldGuard(duration: 0.5)
        _ = guardState.down(app: "a", key: .quit, at: 0)
        #expect(guardState.progress(app: "a", key: .quit, at: 0) == 0)
        #expect(abs(guardState.progress(app: "a", key: .quit, at: 0.25) - 0.5) < 0.0001)
        #expect(guardState.progress(app: "a", key: .quit, at: 2) == 1)
        #expect(guardState.progress(app: "other", key: .quit, at: 0.25) == 0)
    }
}

@Suite struct ModifierDragTests {
    private let start = CGRect(x: 100, y: 200, width: 600, height: 400)

    @Test func movingFollowsThePointerAndKeepsTheSize() {
        let moved = draggedFrame(start: start, from: CGPoint(x: 150, y: 250), to: CGPoint(x: 200, y: 230))
        #expect(moved == CGRect(x: 150, y: 180, width: 600, height: 400))
    }

    @Test func resizingKeepsTheCornerAndNeverGetsTooSmall() {
        let bigger = resizedFrame(start: start, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50))
        #expect(bigger == CGRect(x: 100, y: 200, width: 700, height: 450))
        let tiny = resizedFrame(start: start, from: CGPoint(x: 0, y: 0), to: CGPoint(x: -5000, y: -5000))
        #expect(tiny.width == 180)
        #expect(tiny.height == 120)
        #expect(tiny.origin == start.origin, "resizing never moves the window")
    }

    @Test func onlyTheExactCombinationCounts() {
        let wanted = KeyModifier.control | KeyModifier.command
        #expect(isModifierDrag(flags: wanted, wanted: wanted))
        #expect(!isModifierDrag(flags: wanted | KeyModifier.shift, wanted: wanted), "an extra key is not it")
        #expect(!isModifierDrag(flags: KeyModifier.control, wanted: wanted))
        #expect(!isModifierDrag(flags: 0, wanted: 0), "nothing chosen means never")
    }

    @Test func whatEachModeReactsTo() {
        #expect(ModifierDragMode.move.movesOnLeft)
        #expect(!ModifierDragMode.move.resizesOnRight)
        #expect(ModifierDragMode.resize.resizesOnRight)
        #expect(!ModifierDragMode.resize.movesOnLeft)
        #expect(ModifierDragMode.moveAndResize.movesOnLeft && ModifierDragMode.moveAndResize.resizesOnRight)
        #expect(!ModifierDragMode.off.movesOnLeft && !ModifierDragMode.off.resizesOnRight)
    }
}
