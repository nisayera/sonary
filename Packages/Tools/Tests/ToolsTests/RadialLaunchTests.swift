import Foundation
import SonaryCore
import Testing
@testable import Tools

struct RadialLaunchTests {
    private let safari = RadialLaunch.app(path: "/Applications/Safari.app")
    private let notes = RadialLaunch.file(path: "/Users/me/notes.txt")
    private let shot = RadialLaunch.shortcut(KeyCombo(keyCode: 21, modifiers: KeyModifier.command | KeyModifier.shift))

    @Test func launchesComeAfterTheActionsAndBeforeTheRings() {
        let ring = RadialProfile(name: "More")
        let items = radialRootItems(actions: [.darkMode], launches: [safari, shot], profiles: [ring])
        #expect(items == [.action(.darkMode), .launch(safari), .launch(shot), .profile(ring)])
    }

    @Test func onlyLaunchesStillMakeARing() {
        #expect(radialRootItems(actions: [], launches: [notes], profiles: []) == [.launch(notes)])
    }

    @Test func ringsKeepTheirWayBackWithLaunches() {
        let ring = RadialProfile(name: "Work", actions: [.screenshot], launches: [safari])
        #expect(radialProfileItems(ring) == [.action(.screenshot), .launch(safari), .back])
    }

    @Test func titlesNameTheThingOrTheKeys() {
        #expect(safari.title == "Safari")
        #expect(notes.title == "notes.txt")
        #expect(shot.title == "⇧⌘4")
    }

    @Test func ringsSavedBeforeLaunchesStillRead() throws {
        let old = #"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Old","symbol":"star","actions":["darkMode"]}"#
        let ring = try JSONDecoder().decode(RadialProfile.self, from: Data(old.utf8))
        #expect(ring.launches == nil)
        #expect(radialProfileItems(ring) == [.action(.darkMode), .back])
    }
}

struct CleaningKeyTests {
    @Test func onlyEscapeEndsCleaning() {
        #expect(cleaningVerdict(isKeyDown: true, keyCode: 53) == .stop)
        #expect(cleaningVerdict(isKeyDown: false, keyCode: 53) == .swallow)
        #expect(cleaningVerdict(isKeyDown: true, keyCode: 0) == .swallow)
    }
}
