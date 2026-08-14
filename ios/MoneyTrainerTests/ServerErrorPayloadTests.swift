import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Structured API errors")
struct ServerErrorPayloadTests {
    @Test("Surfaces each dataset validation cause")
    func structuredValidationDetail() throws {
        let data = Data(
            #"{"detail":{"code":"dataset_validation_failed","errors":[{"code":"missing_class","message":"jpy_50の画像が不足しています"},{"code":"missing_test_class","message":"Test Datasetにjpy_5が存在しません"}]}}"#.utf8
        )
        let payload = try JSONCoding.makeDecoder().decode(ServerErrorPayload.self, from: data)

        #expect(payload.detail?.contains("jpy_50") == true)
        #expect(payload.detail?.contains("jpy_5") == true)
    }
}
