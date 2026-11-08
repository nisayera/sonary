import Foundation
import Testing
@testable import Display

@Suite struct DDCTests {
    @Test func aBrightnessWriteIsFramedAndChecksummed() {
        // Length 0x84 (opcode set), 3 payload bytes, luminance 0x10, value 50, XOR seeded 0x6E ^ 0x51.
        #expect(DDCSupport.writePacket(code: 0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func aReplyGivesCurrentAndMaximum() throws {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        let parsed = try #require(DDCSupport.parseReply(reply, code: 0x10))
        #expect(parsed.current == 50)
        #expect(parsed.maximum == 100)
    }

    @Test func aBrokenOrForeignReplyIsIgnored() {
        var corrupted: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        corrupted[9] = 0x33
        #expect(DDCSupport.parseReply(corrupted, code: 0x10) == nil)
        let other: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF0]
        #expect(DDCSupport.parseReply(other, code: 0x10) == nil)
        #expect(DDCSupport.parseReply([0x6E], code: 0x10) == nil)
    }

    @Test func valuesScaleToTheMonitorsRange() {
        #expect(DDCSupport.normalized(current: 50, maximum: 100) == 0.5)
        #expect(DDCSupport.normalized(current: 30, maximum: 0) == 0.3)
        #expect(DDCSupport.deviceValue(for: 0.5, maximum: 255) == 128)
        #expect(DDCSupport.deviceValue(for: 2, maximum: 100) == 100)
    }

    @Test func commandsAreSpacedFiftyMillisecondsApart() {
        #expect(DDCSupport.commandDelay(nowMicroseconds: 1_000, lastCommandEndMicroseconds: nil) == 0)
        #expect(DDCSupport.commandDelay(nowMicroseconds: 20_000, lastCommandEndMicroseconds: 0) == 30_000)
        #expect(DDCSupport.commandDelay(nowMicroseconds: 90_000, lastCommandEndMicroseconds: 0) == 0)
    }

    @Test func theLocationAloneDecidesTheMatch() {
        var service = DDCSupport.ServiceIdentity()
        service.ioDisplayLocation = "IOService:/a/b"
        service.ordinal = 1
        var display = DDCSupport.DisplayIdentity()
        display.ioDisplayLocation = "IOService:/a/b"
        #expect(DDCSupport.matchScore(service: service, display: display) >= 10)
        let assignment = DDCSupport.assignServices(scores: [(0, 1, 10), (0, 2, 1), (1, 1, 2)])
        #expect(assignment == [0: 1])
    }
}
