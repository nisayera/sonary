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
