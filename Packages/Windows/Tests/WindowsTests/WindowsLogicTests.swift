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
