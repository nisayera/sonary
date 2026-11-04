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
