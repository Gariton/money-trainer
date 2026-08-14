import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Model metrics contract")
struct ModelMetricsCodingTests {
    @Test("Decodes canonical training metric keys")
    func decodesTrainingFixture() throws {
        let data = Data(
            #"{"mAP50":0.951,"mAP50-95":0.902,"precision":0.934,"recall":0.913,"perClass":{"jpy_1":{"precision":0.91,"recall":0.89,"AP":0.87,"AP50":0.93}}}"#.utf8
        )
        let metrics = try JSONCoding.makeDecoder().decode(ModelMetrics.self, from: data)

        #expect(abs(metrics.map50 - 0.951) < 0.0001)
        #expect(abs(metrics.map50To95 - 0.902) < 0.0001)
        #expect(abs(try #require(metrics.perClass[.one]).averagePrecision - 0.87) < 0.0001)
    }

    @Test("Decodes the server-normalized snake-case metrics")
    func decodesServerFixture() throws {
        let data = Data(
            #"{"map50":0.982,"map50_95":0.8,"precision":0.987,"recall":0.978,"per_class":{"jpy_100":{"precision":1,"recall":1,"ap":1,"ap50":1}}}"#.utf8
        )
        let metrics = try JSONCoding.makeDecoder().decode(ModelMetrics.self, from: data)

        #expect(abs(metrics.map50 - 0.982) < 0.0001)
        #expect(abs(try #require(metrics.perClass[.oneHundred]).averagePrecision - 1) < 0.0001)
    }
}
