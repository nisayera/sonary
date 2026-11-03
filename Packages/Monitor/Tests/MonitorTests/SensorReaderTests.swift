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
