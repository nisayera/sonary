import Testing
@testable import Monitor

struct SensorReaderTests {
    @Test func dropsNonPositiveAndImplausibleValues() {
        let cleaned = normalizeTemperatures(["a": 0, "b": -5, "c": 151, "d": 400])
        #expect(cleaned.isEmpty)
    }

    @Test func keepsPlausibleValues() {
        #expect(normalizeTemperatures(["CPU": 55.5, "GPU": 150]) == ["CPU": 55.5, "GPU": 150])
    }

    @Test func unavailableSourcesDegradeToNilAndEmpty() {
        let reader = SystemSensorReader(gpu: { nil }, temperatures: { [:] })
        #expect(reader.gpuUsage() == nil)
        #expect(reader.temperatures().isEmpty)
    }

    @Test func gpuUsageIsClampedAndRejectsNaN() {
        #expect(SystemSensorReader(gpu: { 1.7 }, temperatures: { [:] }).gpuUsage() == 1)
        #expect(SystemSensorReader(gpu: { .nan }, temperatures: { [:] }).gpuUsage() == nil)
    }

    @Test func decodesFloatTemperature() {
        #expect(SMCValueDecoder.decode([0x00, 0x00, 0x20, 0x42], type: "flt ") == 40.0)
    }

    @Test func decodesFixedPointTemperature() {
        #expect(SMCValueDecoder.decode([0x2D, 0x80], type: "sp78") == 45.5)
    }

    @Test func unknownTypeDecodesToNil() {
        #expect(SMCValueDecoder.decode([1, 2, 3, 4], type: "ch8*") == nil)
    }
}

struct FanReadingTests {
    @Test func loadSitsBetweenTheEnds() {
        let fan = FanReading(index: 0, rpm: 3000, minimum: 1000, maximum: 5000)
        #expect(fan.load == 0.5)
    }

    @Test func loadNeedsBothEnds() {
        #expect(FanReading(index: 0, rpm: 3000).load == nil)
        #expect(FanReading(index: 0, rpm: 3000, minimum: 2000, maximum: 2000).load == nil)
    }

    @Test func loadStaysInRange() {
        #expect(FanReading(index: 0, rpm: 9000, minimum: 1000, maximum: 5000).load == 1)
        #expect(FanReading(index: 0, rpm: 10, minimum: 1000, maximum: 5000).load == 0)
    }

    @Test func implausibleReadingsAreDropped() {
        let readings = [FanReading(index: 0, rpm: 0), FanReading(index: 1, rpm: 2400),
                        FanReading(index: 2, rpm: 65_535)]
        #expect(plausibleFans(readings).map(\.index) == [1])
    }

    @Test func formatsTheFastestFan() {
        #expect(formatFanSpeed([FanReading(index: 0, rpm: 1200), FanReading(index: 1, rpm: 2400.4)]) == "2400 rpm")
        #expect(formatFanSpeed([]) == "—")
    }

    @Test func fanlessMacReadsNothing() {
        #expect(NoFans().fans().isEmpty)
    }
}
