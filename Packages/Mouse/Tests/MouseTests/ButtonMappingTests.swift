import Testing
@testable import Mouse

struct ButtonMappingTests {
    private let mappings = [ButtonMapping(button: 3, action: .back), ButtonMapping(button: 1, action: .none)]

    @Test func buttonsZeroToTwoNeverMapped() {
        #expect(action(forButton: 0, in: mappings) == nil)
        #expect(action(forButton: 1, in: mappings) == nil)
        #expect(action(forButton: 2, in: mappings) == nil)
    }

    @Test func unmappedButtonReturnsNil() {
        #expect(action(forButton: 4, in: mappings) == nil)
    }

    @Test func mappedButtonReturnsAction() {
        #expect(action(forButton: 3, in: mappings) == .back)
    }
}

struct ShortcutActionTests {
    @Test func aRecordedShortcutReadsLikeTheKeys() {
        let modifiers = shortcutModifiers(command: true, option: false, control: true, shift: false)
        #expect(shortcutLabel(keyCode: 3, modifiers: modifiers) == "⌃⌘F")
        #expect(shortcutLabel(keyCode: 49, modifiers: 0) == "Space")
    }

    @Test func anUnrecordedShortcutShowsNothing() {
        #expect(shortcutLabel(keyCode: unrecordedKeyCode, modifiers: 0).isEmpty)
    }
}
