import Foundation
import Testing
@testable import Tools

struct ToolsLogicTests {
    @Test func hexColorFormatsAndClamps() {
        #expect(hexColor(red: 1, green: 0.5, blue: 0) == "#FF8000")
        #expect(hexColor(red: 2, green: -1, blue: 0.2) == "#FF0033")
    }

    @Test func prefixBeatsWordStartBeatsLetters() throws {
        let prefix = try #require(matchScore("saf", in: "Safari"))
        let word = try #require(matchScore("cen", in: "Game Center"))
        let letters = try #require(matchScore("sfr", in: "Safari"))
        #expect(prefix > word)
        #expect(word > letters)
    }

    @Test func noMatchIsNil() {
        #expect(matchScore("xyz", in: "Safari") == nil)
        #expect(matchScore("", in: "Safari") == 0)
    }

    @Test func shorterTitleWinsOnEqualMatch() throws {
        let short = try #require(matchScore("mail", in: "Mail"))
        let long = try #require(matchScore("mail", in: "Mailspring"))
        #expect(short > long)
    }

    @Test func snippetPlaceholders() {
        let date = Date(timeIntervalSince1970: 0)
        let result = expandSnippet("Hi {clipboard}!", now: date, clipboard: "there")
        #expect(result == "Hi there!")
        #expect(!expandSnippet("{date}", now: date, clipboard: nil).contains("{date}"))
        #expect(expandSnippet("{clipboard}", now: date, clipboard: nil) == "")
    }

    @Test func snippetDatesTakeAFormatOfTheirOwn() {
        // Mid-month at noon UTC, so the date is the same in every time zone.
        let date = Date(timeIntervalSince1970: 1_781_524_800) // 2026-06-15 12:00 UTC
        let result = expandSnippet("Due {date:yyyy-MM}", now: date, clipboard: nil, locale: Locale(identifier: "en_US_POSIX"))
        #expect(result == "Due 2026-06")
    }

    @Test func typingATriggerFindsItsSnippet() {
        let short = Snippet(title: "Sig", text: "Best, Luka", trigger: ";sig")
        let long = Snippet(title: "Sig 2", text: "Cheers", trigger: ";sig2")
        let tooShort = Snippet(title: "One", text: "x", trigger: ";")
        var watcher = SnippetTriggerWatcher()
        #expect(watcher.type(";", snippets: [tooShort]) == nil)
        for character in ";si" { #expect(watcher.type(String(character), snippets: [short]) == nil) }
        #expect(watcher.type("g", snippets: [short]) == short)

        watcher.reset()
        for character in ";sig" { _ = watcher.type(String(character), snippets: [long]) }
        #expect(watcher.type("2", snippets: [short, long]) == long)
    }

    @Test func backspaceAndResetForgetWhatWasTyped() {
        let snippet = Snippet(title: "Sig", text: "Best", trigger: ";sig")
        var watcher = SnippetTriggerWatcher()
        for character in ";six" { _ = watcher.type(String(character), snippets: [snippet]) }
        watcher.backspace()
        #expect(watcher.type("g", snippets: [snippet]) == snippet)

        for character in ";si" { _ = watcher.type(String(character), snippets: [snippet]) }
        watcher.reset()
        #expect(watcher.type("g", snippets: [snippet]) == nil)
    }

    @Test func recognizedLinesAreJoined() {
        #expect(joinRecognizedLines(["  Hello ", "", "World"]) == "Hello\nWorld")
    }
}

struct RadialMathTests {
    private let center = CGPoint(x: 100, y: 100)

    @Test func angleIsClockwiseFromTop() {
        #expect(radialAngle(from: center, to: CGPoint(x: 100, y: 200)) == 0)
        #expect(radialAngle(from: center, to: CGPoint(x: 200, y: 100)) == 90)
        #expect(radialAngle(from: center, to: CGPoint(x: 100, y: 0)) == 180)
        #expect(radialAngle(from: center, to: CGPoint(x: 0, y: 100)) == 270)
    }

    @Test func firstWedgePointsUp() {
        #expect(radialSector(angle: 0, count: 8) == 0)
        #expect(radialSector(angle: 10, count: 8) == 0)
        #expect(radialSector(angle: 350, count: 8) == 0)
    }

    @Test func wedgesFollowClockwise() {
        #expect(radialSector(angle: 45, count: 8) == 1)
        #expect(radialSector(angle: 180, count: 8) == 4)
        #expect(radialSector(angle: 315, count: 8) == 7)
    }

    @Test func singleWedgeTakesEverything() {
        #expect(radialSector(angle: 200, count: 1) == 0)
        #expect(radialSector(angle: 0, count: 0) == 0)
    }

    @Test func centerCancels() {
        #expect(radialSelection(center: center, point: CGPoint(x: 105, y: 105), count: 8) == nil)
        #expect(radialSelection(center: center, point: CGPoint(x: 100, y: 180), count: 8) == 0)
    }

    @Test func itemsSitOnTheRing() {
        let first = radialItemOffset(index: 0, count: 4, radius: 100)
        #expect(abs(first.x) < 0.001 && abs(first.y - 100) < 0.001)
        let second = radialItemOffset(index: 1, count: 4, radius: 100)
        #expect(abs(second.x - 100) < 0.001 && abs(second.y) < 0.001)
    }

    @Test func quickTogglesAreSystemActionsOnly() {
        #expect(quickToggleActions.allSatisfy { ![.commandBar, .textFromScreen, .colorPicker, .screenshot].contains($0) })
        #expect(quickToggleActions.contains(.cleaningMode))
    }
}

struct CalculatorTests {
    @Test func doesArithmetic() {
        #expect(evaluateExpression("2+2") == "4")
        #expect(evaluateExpression("12*(3+4)/2") == "42")
        #expect(evaluateExpression("10/4") == "2.5")
    }

    @Test func leavesNonMathsAlone() {
        #expect(evaluateExpression("safari") == nil)
        #expect(evaluateExpression("2") == nil)
        #expect(evaluateExpression("rm -rf /") == nil)
        #expect(evaluateExpression("open -a Mail") == nil)
    }

    @Test func survivesDivisionByZero() {
        #expect(evaluateExpression("5/0") == nil)
    }

    @Test func formatsWithoutTrailingZeros() {
        #expect(formatNumber(3.0) == "3")
        #expect(formatNumber(3.5000) == "3.5")
        #expect(formatNumber(2.0 / 3.0) == "0.666667")
    }
}

struct UnitConversionTests {
    @Test func convertsLengthAndMass() {
        #expect(convertUnits("10 km in mi")?.hasPrefix("6.21") == true)
        #expect(convertUnits("5 lb in kg")?.hasPrefix("2.26") == true)
    }

    @Test func convertsTemperature() {
        #expect(convertUnits("20 c to f")?.hasPrefix("68") == true)
    }

    @Test func convertsDataSizes() {
        #expect(convertUnits("1 gb in mb")?.hasPrefix("1000") == true)
    }

    @Test func ignoresWhatIsNotAConversion() {
        #expect(convertUnits("hello world") == nil)
        #expect(convertUnits("10 km in bananas") == nil)
        #expect(convertUnits("km in mi") == nil)
    }
}

struct EmojiSearchTests {
    @Test func findsByName() {
        #expect(searchEmoji("rocket").first?.emoji == "🚀")
        #expect(searchEmoji("thumbs").contains { $0.emoji == "👍" })
    }

    @Test func needsTwoLetters() {
        #expect(searchEmoji("r").isEmpty)
        #expect(searchEmoji("").isEmpty)
    }

    @Test func unknownWordFindsNothing() {
        #expect(searchEmoji("qqqq").isEmpty)
    }
}

struct CalculatorRobustnessTests {
    @Test func handlesParenthesesAndPrecedence() {
        #expect(evaluateExpression("2+3*4") == "14")
        #expect(evaluateExpression("(2+3)*4") == "20")
        #expect(evaluateExpression("2^3^2") == "512")
    }

    @Test func handlesNegativeNumbers() {
        #expect(evaluateExpression("-5+2") == "-3")
        #expect(evaluateExpression("3*-2") == "-6")
    }

    @Test func rejectsBrokenInputInsteadOfCrashing() {
        for broken in ["((2+3", "2++", "*5", "()+1", "2+)3(", "1/(2-2)", "-+*/"] {
            #expect(evaluateExpression(broken) == nil, "should refuse \(broken)")
        }
    }

    @Test func acceptsCommaAsDecimalSeparator() {
        #expect(evaluateExpression("1,5*2") == "3")
    }
}

struct ColorFormatTests {
    @Test func writesEveryFormat() {
        #expect(formatColor(red: 1, green: 0.5, blue: 0, format: .hex) == "#FF8000")
        #expect(formatColor(red: 1, green: 0.5, blue: 0, format: .rgb) == "rgb(255, 128, 0)")
        #expect(formatColor(red: 1, green: 0.5, blue: 0, format: .hsl) == "hsl(30, 100%, 50%)")
        #expect(formatColor(red: 1, green: 0.5, blue: 0, format: .swiftUI) == "Color(red: 1, green: 0.5, blue: 0)")
    }

    @Test func greyHasNoHue() {
        #expect(formatColor(red: 0.5, green: 0.5, blue: 0.5, format: .hsl) == "hsl(0, 0%, 50%)")
    }

    @Test func clampsOutOfRangeValues() {
        #expect(formatColor(red: 2, green: -1, blue: 0.5, format: .rgb) == "rgb(255, 0, 128)")
    }

    @Test func hueFollowsTheColourWheel() {
        #expect(Int(hsl(r: 1, g: 0, b: 0).hue.rounded()) == 0)
        #expect(Int(hsl(r: 0, g: 1, b: 0).hue.rounded()) == 120)
        #expect(Int(hsl(r: 0, g: 0, b: 1).hue.rounded()) == 240)
    }
}

struct ScratchpadTests {
    @Test func fileNameLosesAwkwardCharacters() {
        #expect(exportFileName(for: "Plan: 2026/Q1") == "Plan  2026 Q1.md")
        #expect(exportFileName(for: "   ") == "Note.md")
    }

    @Test func fileNameStaysShort() {
        #expect(exportFileName(for: String(repeating: "a", count: 200)).count == 63)
    }

    @Test func titleComesFromTheFirstLine() {
        #expect(suggestedTitle(for: "# Shopping\nmilk", fallback: "Note") == "Shopping")
        #expect(suggestedTitle(for: "", fallback: "Note") == "Note")
        #expect(suggestedTitle(for: "\n\nlater", fallback: "Note") == "later")
        #expect(suggestedTitle(for: "\n\n   ", fallback: "Note") == "Note")
    }

    @Test func tabsCanBeReordered() {
        let tabs = [ScratchpadTab(title: "a"), ScratchpadTab(title: "b"), ScratchpadTab(title: "c")]
        #expect(movedTab(tabs, from: 0, to: 2).map(\.title) == ["b", "c", "a"])
        #expect(movedTab(tabs, from: 5, to: 0).map(\.title) == ["a", "b", "c"])
        #expect(movedTab(tabs, from: 1, to: 1).map(\.title) == ["a", "b", "c"])
    }
}

struct MenuCommandTests {
    @Test func keepsRealCommands() {
        let commands = [MenuCommand(path: ["File", "Save"]), MenuCommand(path: ["Edit", "Copy"])]
        #expect(usefulMenuCommands(commands).map(\.title) == ["File ▸ Save", "Edit ▸ Copy"])
    }

    @Test func dropsAppleAndHelpMenus() {
        let commands = [MenuCommand(path: ["Apple", "Sleep"]), MenuCommand(path: ["Help", "Search"]),
                        MenuCommand(path: ["Window", "Zoom"]), MenuCommand(path: ["File", "Open"])]
        #expect(usefulMenuCommands(commands).map(\.title) == ["File ▸ Open"])
    }

    @Test func dropsSeparatorsAndTopLevelOnly() {
        let commands = [MenuCommand(path: ["File"]), MenuCommand(path: ["File", "-"]),
                        MenuCommand(path: ["File", ""]), MenuCommand(path: ["File", "Close"])]
        #expect(usefulMenuCommands(commands).map(\.title) == ["File ▸ Close"])
    }

    @Test func dropsDuplicates() {
        let commands = [MenuCommand(path: ["File", "Save"]), MenuCommand(path: ["File", "Save"])]
        #expect(usefulMenuCommands(commands).count == 1)
    }

    @Test func respectsTheLimit() {
        let commands = (0..<50).map { MenuCommand(path: ["File", "Item \($0)"]) }
        #expect(usefulMenuCommands(commands, limit: 10).count == 10)
    }
}

@Suite struct MediaToolTests {
    @Test func keepsImagesThatAreAlreadySmallEnough() {
        let big = scaledSize(width: 800, height: 600, longestEdge: 1200)
        #expect(big.width == 800)
        #expect(big.height == 600)
        let off = scaledSize(width: 800, height: 600, longestEdge: 0)
        #expect(off.width == 800)
        #expect(off.height == 600)
        let empty = scaledSize(width: 0, height: 0, longestEdge: 100)
        #expect(empty.width == 0)
        #expect(empty.height == 0)
    }

    @Test func scalesTheLongestEdgeAndKeepsTheRatio() {
        let landscape = scaledSize(width: 4000, height: 3000, longestEdge: 1000)
        #expect(landscape.width == 1000)
        #expect(landscape.height == 750)
        let portrait = scaledSize(width: 3000, height: 4000, longestEdge: 1000)
        #expect(portrait.width == 750)
        #expect(portrait.height == 1000)
        let thin = scaledSize(width: 10_000, height: 3, longestEdge: 100)
        #expect(thin.height >= 1)
    }

    @Test func neverOverwritesAnExistingExport() {
        let source = URL(fileURLWithPath: "/tmp/pictures/Shot.heic")
        let taken = ["Shot.jpg"]
        let url = exportURL(for: source, format: .jpeg) { taken.contains($0) }
        #expect(url.lastPathComponent == "Shot 2.jpg")
        #expect(url.deletingLastPathComponent().path == "/tmp/pictures")
    }

    @Test func formatsCarryTheirExtension() {
        #expect(ImageFormat.jpeg.fileExtension == "jpg")
        #expect(ImageFormat.allCases.allSatisfy { !$0.fileExtension.isEmpty })
    }

    @Test func recordingNamesAreStampedAndSafe() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 14, minute: 2, second: 9))!
        let name = recordingFileName(now: date, calendar: calendar)
        #expect(name == "Sonary 2026-07-01 at 14.02.09.mp4")
    }

    @Test func bitrateStaysInAReasonableRange() {
        #expect(recordingBitrate(width: 320, height: 240) == 2_000_000)
        #expect(recordingBitrate(width: 7680, height: 4320) == 40_000_000)
        let retina = recordingBitrate(width: 2560, height: 1440)
        #expect(retina > 2_000_000 && retina < 40_000_000)
    }
}

@Suite struct GIFPlanTests {
    @Test func spreadsFramesOverTheClip() {
        let plan = gifPlan(duration: 4, fps: 10)
        #expect(plan.frames == 40)
        #expect(abs(plan.delay - 0.1) < 0.0001)
    }

    @Test func capsALongClipInsteadOfExploding() {
        let plan = gifPlan(duration: 600, fps: 10, maxFrames: 240)
        #expect(plan.frames == 240)
        #expect(abs(plan.delay - 2.5) < 0.0001, "the same clip, just coarser")
    }

    @Test func survivesAClipWithNoLength() {
        let plan = gifPlan(duration: 0, fps: 10)
        #expect(plan.frames == 1)
        #expect(plan.delay > 0)
        #expect(gifSampleTimes(duration: 0, frames: 0) == [0])
    }

    @Test func samplesStartAtZeroAndStayInsideTheClip() {
        let times = gifSampleTimes(duration: 4, frames: 4)
        #expect(times.count == 4)
        #expect(times.first == 0)
        #expect(times.allSatisfy { $0 < 4 })
    }
}

@Suite struct CaptureSelectionTests {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func aDragInAnyDirectionGivesTheSameRectangle() {
        let downRight = selectionRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        let upLeft = selectionRect(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 100))
        #expect(downRight == upLeft)
        #expect(downRight == CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    @Test func aSelectionStaysOnItsScreen() {
        let over = CGRect(x: -50, y: -50, width: 200, height: 200)
        #expect(clampSelection(over, to: screen) == CGRect(x: 0, y: 0, width: 150, height: 150))
    }

    @Test func aStraySmallDragCapturesNothing() {
        #expect(!isSelectionUsable(CGRect(x: 0, y: 0, width: 2, height: 80)))
        #expect(!isSelectionUsable(.zero))
        #expect(isSelectionUsable(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test func showsThePixelSizeWhileDragging() {
        #expect(selectionSizeLabel(CGRect(x: 0, y: 0, width: 200.4, height: 149.6)) == "200 × 150")
    }

    @Test func theMagnifierNeverLooksOffTheScreen() {
        let corner = magnifierSource(at: CGPoint(x: 0, y: 0), in: screen, side: 24)
        #expect(screen.contains(corner))
        #expect(corner.width == 24 && corner.height == 24)
        let farCorner = magnifierSource(at: CGPoint(x: 1600, y: 1000), in: screen, side: 24)
        #expect(screen.contains(farCorner))
        let middle = magnifierSource(at: CGPoint(x: 800, y: 500), in: screen, side: 24)
        #expect(middle == CGRect(x: 788, y: 488, width: 24, height: 24))
    }

    @Test func theLoupeMovesOutOfItsOwnWay() {
        let normal = magnifierPlacement(at: CGPoint(x: 100, y: 100), in: screen, size: 120, gap: 16)
        #expect(normal == CGPoint(x: 116, y: 116))
        let nearEdge = magnifierPlacement(at: CGPoint(x: 1590, y: 990), in: screen, size: 120, gap: 16)
        #expect(nearEdge.x < 1590)
        #expect(nearEdge.y < 990)
        #expect(nearEdge.x >= 0 && nearEdge.y >= 0)
    }
}

@Suite struct TypeTextTests {
    @MainActor
    @Test func splitsTextIntoChunksTheEventCanCarry() {
        let chunks = TypeText.chunks(of: String(repeating: "a", count: 40), size: 16)
        #expect(chunks.count == 3)
        #expect(chunks.map(\.count) == [16, 16, 8])
    }

    @MainActor
    @Test func keepsEmojiAndAccentsWhole() {
        // Characters outside the basic plane take two UTF-16 units; nothing may be lost.
        let text = "Grüße 🙂"
        let units = TypeText.chunks(of: text, size: 4).flatMap { $0 }
        #expect(String(decoding: units, as: UTF16.self) == text)
    }

    @MainActor
    @Test func nothingToTypeIsNoChunks() {
        #expect(TypeText.chunks(of: "").isEmpty)
        #expect(TypeText.chunks(of: "abc", size: 0).isEmpty)
    }
}

@Suite struct RadialProfileTests {
    private let profile = RadialProfile(name: "Capture", actions: [.screenshot, .pinScreenshot])

    @Test func theFirstRingHoldsActionsThenRings() {
        let items = radialRootItems(actions: [.darkMode, .lockScreen], profiles: [profile])
        #expect(items.count == 3)
        #expect(items[0] == .action(.darkMode))
        #expect(items[2] == .profile(profile), "a new ring never moves the actions already there")
    }

    @Test func anEmptyChoiceMeansEverything() {
        let items = radialRootItems(actions: [], profiles: [])
        #expect(items.count == min(QuickAction.allCases.count, radialRingLimit))
    }

    @Test func aRingNeverGetsTooCrowded() {
        let many = (0..<6).map { RadialProfile(name: "r\($0)") }
        let items = radialRootItems(actions: QuickAction.allCases, profiles: many)
        #expect(items.count == radialRingLimit)
    }

    @Test func aProfileRingKeepsAWayBack() {
        let items = radialProfileItems(profile)
        #expect(items.first == .action(.screenshot))
        #expect(items.last == .back)
        let crowded = RadialProfile(name: "all", actions: QuickAction.allCases)
        #expect(radialProfileItems(crowded).count == radialRingLimit)
        #expect(radialProfileItems(crowded).last == .back, "the way back is never pushed out")
    }

    @Test func itemsAreTellableApart() {
        #expect(RadialItem.action(.darkMode).id != RadialItem.action(.lockScreen).id)
        #expect(RadialItem.profile(profile).id != RadialItem.back.id)
        #expect(RadialItem.back.symbol == "chevron.backward")
    }
}

@Suite struct FileSearchTests {
    @Test func tooShortToBeWorthAsking() {
        #expect(!isWorthSearching(""))
        #expect(!isWorthSearching("ab"))
        #expect(!isWorthSearching("  a  "))
        #expect(isWorthSearching("abc"))
    }

    @Test func aStrayQuoteCannotChangeTheQuestion() {
        let predicate = fileSearchPredicate("my \"file\" \\ name")
        #expect(predicate == "kMDItemDisplayName CONTAINS[cd] \"my file  name\"")
        #expect(predicate.filter { $0 == "\"" }.count == 2, "only the two quotes we put there")
    }
}

@Suite struct ScriptTests {
    private func file(_ name: String, executable: Bool = true, directory: Bool = false)
    -> (url: URL, isExecutable: Bool, isDirectory: Bool) {
        (URL(fileURLWithPath: "/tmp/scripts/\(name)"), executable, directory)
    }

    @Test func onlyExecutableFilesAreOffered() {
        let found = usableScripts([
            file("backup.sh"),
            file("notes.txt", executable: false),
            file("tools", directory: true),
            file(".hidden"),
        ])
        #expect(found.map(\.name) == ["backup"])
    }

    @Test func scriptsAreListedByName() {
        let found = usableScripts([file("zip-it.sh"), file("archive.sh"), file("Backup.command")])
        #expect(found.map(\.name) == ["archive", "Backup", "zip-it"])
    }

    @Test func theFolderSitsInSonarysOwnSupportFolder() {
        let folder = scriptsFolder(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(folder.path == "/Users/someone/Library/Application Support/app.sonary.Sonary/Scripts")
    }
}

@Suite struct AnnotationTests {
    private func mark(_ kind: AnnotationKind, from start: CGPoint, to end: CGPoint, text: String = "")
    -> Annotation {
        Annotation(kind: kind, start: start, end: end, text: text)
    }

    @Test func aMarkCoversTheSameAreaWhicheverWayItWasDrawn() {
        let down = mark(.rectangle, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 90))
        let up = mark(.rectangle, from: CGPoint(x: 60, y: 90), to: CGPoint(x: 10, y: 10))
        #expect(down.frame == up.frame)
        #expect(down.frame == CGRect(x: 10, y: 10, width: 50, height: 80))
    }

    @Test func straySmallMarksAreDropped() {
        #expect(!isAnnotationWorthKeeping(mark(.rectangle, from: .zero, to: CGPoint(x: 3, y: 3))))
        #expect(isAnnotationWorthKeeping(mark(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20))))
        #expect(isAnnotationWorthKeeping(mark(.arrow, from: .zero, to: CGPoint(x: 10, y: 2))),
                "a short arrow still points somewhere")
        #expect(!isAnnotationWorthKeeping(mark(.arrow, from: .zero, to: CGPoint(x: 4, y: 2))))
    }

    @Test func textWithoutTextIsNotAMark() {
        #expect(!isAnnotationWorthKeeping(mark(.text, from: .zero, to: CGPoint(x: 100, y: 40))))
        #expect(isAnnotationWorthKeeping(mark(.text, from: .zero, to: .zero, text: "look here")))
    }

    @Test func redactionBlocksAreCoarseEnoughToDestroyTheContent() {
        #expect(redactionBlockSize(for: CGRect(x: 0, y: 0, width: 800, height: 80)) == 10)
        #expect(redactionBlockSize(for: CGRect(x: 0, y: 0, width: 20, height: 20)) == 6,
                "never finer than six pixels, however small the area")
        #expect(redactionBlockSize(for: .zero) == 1)
    }

    @Test func aBackgroundDecidesWhetherThereIsAMargin() {
        #expect(ExportBackground.none.margin(48) == 0, "a plain export is pixel for pixel the shot")
        #expect(ExportBackground.white.margin(48) == 48)
        let size = exportSize(image: CGSize(width: 800, height: 600), margin: 48)
        #expect(size == CGSize(width: 896, height: 696))
        #expect(exportImageOrigin(margin: 48) == CGPoint(x: 48, y: 48))
    }

    @Test func undoingTakesTheLastOneAndCopesWithNone() {
        let marks = [mark(.arrow, from: .zero, to: CGPoint(x: 20, y: 20)),
                     mark(.rectangle, from: .zero, to: CGPoint(x: 30, y: 30))]
        #expect(undoing(marks).count == 1)
        #expect(undoing(marks).first?.kind == .arrow)
        #expect(undoing([]).isEmpty)
    }

    @Test func whatIsFilledAndWhatIsOutlined() {
        #expect(AnnotationKind.redact.isFilled)
        #expect(AnnotationKind.highlight.isFilled)
        #expect(!AnnotationKind.rectangle.isFilled)
    }
}

@Suite struct ScrollingCaptureTests {
    @Test func findsWhereTheNextShotCarriesOn() {
        // The last four rows of the first shot are the first four of the second.
        let previous: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
        let next: [UInt64] = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        #expect(overlapRows(previous: previous, next: next, minimumOverlap: 4) == 4)
    }

    @Test func twoShotsThatShareNothingAreJustJoined() {
        let previous: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
        let next: [UInt64] = [20, 21, 22, 23, 24, 25, 26, 27]
        #expect(overlapRows(previous: previous, next: next, minimumOverlap: 4) == nil)
    }

    @Test func tooFewRowsToJudge() {
        #expect(overlapRows(previous: [1, 2], next: [1, 2], minimumOverlap: 8) == nil)
        #expect(overlapRows(previous: [], next: [], minimumOverlap: 8) == nil)
    }

    @Test func theLargestOverlapWinsOnARepeatingPage() {
        // Every row looks the same, as on a page of identical list items.
        let rows = [UInt64](repeating: 7, count: 10)
        #expect(overlapRows(previous: rows, next: rows, minimumOverlap: 4) == 10,
                "the whole shot is the same, so nothing new was captured")
    }

    @Test func aShotThatAddsNothingMeansThePageStopped() {
        let rows: [UInt64] = [1, 2, 3]
        #expect(hasStoppedScrolling(previous: rows, next: rows))
        #expect(!hasStoppedScrolling(previous: rows, next: [1, 2, 4]))
        #expect(!hasStoppedScrolling(previous: [], next: []), "nothing captured yet is not a stop")
    }

    @Test func theFinishedHeightCountsEachShotOnce() {
        #expect(stitchedHeight(shots: [100, 100, 100], overlaps: [20, 20]) == 260)
        #expect(stitchedHeight(shots: [100], overlaps: []) == 100)
        #expect(stitchedHeight(shots: [], overlaps: []) == 0)
        #expect(stitchedHeight(shots: [100, 100], overlaps: [nil]) == 200, "no overlap means both in full")
        #expect(stitchedHeight(shots: [100, 100], overlaps: [100]) == 100, "a shot that adds nothing adds nothing")
    }
}
