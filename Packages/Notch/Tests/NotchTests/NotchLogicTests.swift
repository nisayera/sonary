import CoreGraphics
import Foundation
import Testing
@testable import Notch

struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func realNotchUsesAuxiliaryAreas() {
        let size = NotchGeometry.notchSize(screenFrame: screen, safeAreaTop: 32,
                                           auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 24)
        #expect(size == CGSize(width: 192, height: 32))
    }

    @Test func noNotchIsSimulated() {
        let size = NotchGeometry.notchSize(screenFrame: screen, safeAreaTop: 0,
                                           auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 30)
        #expect(size == CGSize(width: NotchGeometry.simulatedWidth, height: 30))
    }

    @Test func simulatedHeightHasMinimum() {
        let size = NotchGeometry.notchSize(screenFrame: screen, safeAreaTop: 0,
                                           auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 0)
        #expect(size.height == NotchGeometry.minimumHeight)
    }

    @Test func panelFrameIsTopCentered() {
        let frame = NotchGeometry.panelFrame(size: CGSize(width: 200, height: 40),
                                             screenFrame: CGRect(x: 1000, y: 0, width: 2000, height: 1000))
        #expect(frame == CGRect(x: 1900, y: 960, width: 200, height: 40))
    }
}

struct NotchStateTests {
    @Test func hoverExpandsAndCollapses() {
        var state = NotchState()
        #expect(state.presentation == .collapsed)
        state.hoverChanged(true)
        #expect(state.presentation == .expanded)
        state.hoverChanged(false)
        #expect(state.presentation == .collapsed)
    }

    @Test func clickPinsOpen() {
        var state = NotchState()
        state.hoverChanged(true)
        state.clicked()
        state.hoverChanged(false)
        #expect(state.presentation == .expanded)
    }

    @Test func secondClickUnpins() {
        var state = NotchState()
        state.clicked()
        state.clicked()
        #expect(state.presentation == .collapsed)
    }

    @Test func clickOutsideUnpins() {
        var state = NotchState()
        state.clicked()
        state.clickedOutside()
        #expect(state.presentation == .collapsed)
    }
}

struct NowPlayingTests {
    @Test func parsesMusicPlaying() {
        let info: [String: Any] = ["Name": "Song", "Artist": "Band", "Album": "Record", "Player State": "Playing"]
        #expect(parseNowPlaying(info, player: .music)
            == NowPlaying(title: "Song", artist: "Band", album: "Record", isPlaying: true, player: .music))
    }

    @Test func parsesSpotifyPaused() {
        let info: [String: Any] = ["Name": "Track", "Artist": "Artist", "Player State": "Paused"]
        let result = parseNowPlaying(info, player: .spotify)
        #expect(result?.isPlaying == false)
        #expect(result?.album == "")
        #expect(result?.player == .spotify)
    }

    @Test func stoppedIsNil() {
        #expect(parseNowPlaying(["Name": "Song", "Player State": "Stopped"], player: .music) == nil)
    }

    @Test func missingTitleIsNil() {
        #expect(parseNowPlaying(["Player State": "Playing"], player: .music) == nil)
    }
}

struct CountdownTimerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func remainingCountsDown() {
        var timer = CountdownTimer()
        timer.start(duration: 300, at: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(60)) == 240)
        #expect(!timer.isFinished(at: t0.addingTimeInterval(60)))
    }

    @Test func neverNegative() {
        var timer = CountdownTimer()
        timer.start(duration: 10, at: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(100)) == 0)
        #expect(timer.isFinished(at: t0.addingTimeInterval(100)))
    }

    @Test func cancelClears() {
        var timer = CountdownTimer()
        timer.start(duration: 10, at: t0)
        timer.cancel()
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: t0) == 0)
    }

    @Test func formatsMinutesAndHours() {
        #expect(formatCountdown(245) == "4:05")
        #expect(formatCountdown(3723) == "1:02:03")
    }
}

struct DownloadsTests {
    private func entry(_ name: String, _ seconds: TimeInterval) -> DownloadEntry {
        DownloadEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), modified: Date(timeIntervalSince1970: seconds))
    }

    @Test func newestFirst() {
        let result = recentDownloads([entry("a.pdf", 1), entry("b.zip", 3), entry("c.png", 2)], limit: 5)
        #expect(result.map(\.url.lastPathComponent) == ["b.zip", "c.png", "a.pdf"])
    }

    @Test func skipsPartialAndHidden() {
        let result = recentDownloads([entry(".DS_Store", 9), entry("big.zip.crdownload", 8),
                                      entry("x.download", 7), entry("ok.dmg", 1)], limit: 5)
        #expect(result.map(\.url.lastPathComponent) == ["ok.dmg"])
    }

    @Test func respectsLimit() {
        let result = recentDownloads((0..<10).map { entry("f\($0)", TimeInterval($0)) }, limit: 3)
        #expect(result.count == 3)
    }
}

struct AccessoryBatteryTests {
    @Test func parsesProducts() {
        let result = parseAccessoryBatteries([
            ["Product": "Magic Mouse", "BatteryPercent": NSNumber(value: 80)],
            ["Product": "AirPods Pro", "BatteryPercent": NSNumber(value: 55)],
        ])
        #expect(result == [AccessoryBattery(name: "AirPods Pro", percent: 55), AccessoryBattery(name: "Magic Mouse", percent: 80)])
    }

    @Test func skipsWithoutPercent() {
        #expect(parseAccessoryBatteries([["Product": "Keyboard"]]).isEmpty)
    }

    @Test func clampsPercent() {
        #expect(parseAccessoryBatteries([["Product": "X", "BatteryPercent": NSNumber(value: 140)]]).first?.percent == 100)
    }

    @Test func deduplicates() {
        let result = parseAccessoryBatteries([
            ["Product": "Mouse", "BatteryPercent": NSNumber(value: 50)],
            ["Product": "Mouse", "BatteryPercent": NSNumber(value: 50)],
        ])
        #expect(result.count == 1)
    }
}

struct NotchSettingsTests {
    @Test func defaultsAsDocumented() {
        let settings = NotchSettings()
        #expect(settings.isOn(.music) && settings.isOn(.timer) && settings.isOn(.downloads) && settings.isOn(.batteries))
        #expect(!settings.isOn(.calendar))
        #expect(settings.showOnScreensWithoutNotch)
    }

    @Test func settingsRoundTrip() {
        let defaults = UserDefaults(suiteName: "sonary.notchtests.\(UUID().uuidString)")!
        let store = NotchSettingsStore(defaults: defaults)
        var settings = NotchSettings()
        settings.set(.calendar, on: true)
        settings.set(.music, on: false)
        settings.showOnScreensWithoutNotch = false
        store.save(settings)
        #expect(store.load() == settings)
        // A widget turned on goes last, so the order the user picked stays.
        #expect(store.load().widgets == [.timer, .downloads, .batteries, .calendar])
    }
}

struct NotchGestureTests {
    @Test func smallScrollsDoNothingUntilTheyAddUp() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: 0, deltaY: -5, presentation: .collapsed) == nil)
        #expect(state.scrolled(deltaX: 0, deltaY: -5, presentation: .collapsed) == nil)
        #expect(state.scrolled(deltaX: 0, deltaY: -5, presentation: .collapsed) == .open)
    }

    @Test func scrollingUpOnTheClosedIslandDoesNothing() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: 0, deltaY: 30, presentation: .collapsed) == nil)
    }

    @Test func scrollingUpClosesTheOpenIsland() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: 0, deltaY: 20, presentation: .expanded) == .close)
    }

    @Test func sidewaysSwitchesWidgetsOnlyWhenOpen() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: -20, deltaY: 0, presentation: .collapsed) == nil)
        state.reset()
        #expect(state.scrolled(deltaX: -20, deltaY: 0, presentation: .expanded) == .nextWidget)
        #expect(state.scrolled(deltaX: 20, deltaY: 0, presentation: .expanded) == .previousWidget)
    }

    @Test func theBiggerDirectionWins() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: -20, deltaY: -14, presentation: .expanded) == .nextWidget)
    }

    @Test func actionResetsTheCollectedMovement() {
        var state = NotchGestureState(threshold: 12)
        #expect(state.scrolled(deltaX: 0, deltaY: -20, presentation: .collapsed) == .open)
        #expect(state.scrolled(deltaX: 0, deltaY: -5, presentation: .expanded) == nil)
    }

    @Test func neighbourWrapsAround() {
        let widgets: [NotchWidget] = [.music, .timer, .downloads]
        #expect(neighbourWidget(.music, in: widgets, forward: true) == .timer)
        #expect(neighbourWidget(.downloads, in: widgets, forward: true) == .music)
        #expect(neighbourWidget(.music, in: widgets, forward: false) == .downloads)
        #expect(neighbourWidget(.music, in: [.music], forward: true) == nil)
        #expect(neighbourWidget(.calendar, in: widgets, forward: true) == .music)
    }
}

@Suite struct FileShelfTests {
    @MainActor
    @Test func keepsTheNewestFirstAndIgnoresRepeats() {
        let shelf = FileShelf()
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")
        shelf.add([a])
        shelf.add([b])
        #expect(shelf.files == [b, a])
        shelf.add([a])
        #expect(shelf.files == [b, a], "a file already on the shelf is not added twice")
    }

    @MainActor
    @Test func dropsTheOldestPastTheLimit() {
        let shelf = FileShelf()
        shelf.add((0..<(shelfLimit + 5)).map { URL(fileURLWithPath: "/tmp/\($0).txt") })
        #expect(shelf.files.count == shelfLimit)
        #expect(shelf.files.first?.lastPathComponent == "0.txt", "the drop order is kept")
    }

    @MainActor
    @Test func pruningRemovesWhatIsNoLongerThere() {
        let shelf = FileShelf()
        shelf.add([URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString).txt")])
        #expect(shelf.files.count == 1)
        shelf.prune()
        #expect(shelf.files.isEmpty)
    }

    @Test func shortensLongNamesInTheMiddle() {
        #expect(shelfLabel("short.txt") == "short.txt")
        let long = shelfLabel("a-very-long-file-name-indeed.txt")
        #expect(long.count <= 19)
        #expect(long.contains("…"))
        #expect(long.hasSuffix(".txt"))
    }
}

struct NotchGapTests {
    @Test func widgetsMoveOnePlaceAtATime() {
        var settings = NotchSettings()
        settings.widgets = [.music, .timer, .downloads]
        settings.move(.downloads, forward: true)
        #expect(settings.widgets == [.music, .downloads, .timer])
        settings.move(.music, forward: true)
        #expect(settings.widgets == [.music, .downloads, .timer], "the first one stays first")
        settings.move(.music, forward: false)
        #expect(settings.widgets == [.downloads, .music, .timer])
    }

    @Test func aLowBatteryWarnsOnceUntilItIsCharged() {
        let low = [AccessoryBattery(name: "Mouse", percent: 18), AccessoryBattery(name: "Keyboard", percent: 60)]
        let first = lowBatteryAlerts(low, warned: [])
        #expect(first.alerts.map(\.name) == ["Mouse"])
        let again = lowBatteryAlerts([AccessoryBattery(name: "Mouse", percent: 15)], warned: first.warned)
        #expect(again.alerts.isEmpty)
        let charged = lowBatteryAlerts([AccessoryBattery(name: "Mouse", percent: 80)], warned: again.warned)
        #expect(charged.warned.isEmpty)
        #expect(lowBatteryAlerts([AccessoryBattery(name: "Mouse", percent: 20)], warned: charged.warned).alerts.count == 1)
    }

    @Test func aBatteryJustAboveTheLineKeepsItsWarning() {
        let result = lowBatteryAlerts([AccessoryBattery(name: "Mouse", percent: 23)], warned: ["Mouse"])
        #expect(result.warned == ["Mouse"])
    }

    @Test func theMonthGridStartsOnTheFirstWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        let november = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let grid = monthGrid(for: november, calendar: calendar)
        // 1 November 2026 is a Sunday: six empty cells before it when weeks start on Monday.
        #expect(grid.prefix(6).allSatisfy { $0 == nil })
        #expect(grid[6].map { calendar.component(.day, from: $0) } == 1)
        #expect(grid.compactMap { $0 }.count == 30)
        #expect(weekdaySymbols(calendar: calendar).count == 7)
    }
}

struct TimerPresetTests {
    @Test func typedMinutesBecomePresets() {
        #expect(parseTimerPresets("25, 5,1 5;90") == [1, 5, 25, 90])
        #expect(parseTimerPresets("0, 700, x") == [])
        #expect(parseTimerPresets("1 2 3 4 5 6") == [1, 2, 3, 4, 5])
    }
}
