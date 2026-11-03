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
