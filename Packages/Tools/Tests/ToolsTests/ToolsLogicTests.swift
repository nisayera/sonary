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
        #expect(quickToggleActions.count == 5)
    }
}
