import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Failure report service")
struct FailureReportServiceTests {
    @Test("Decodes report items and builds the authenticated relative request path")
    func reportContract() async throws {
        let response = Data(
            #"{"items":[{"category":"false_positives","path":"false-positives/example.png","content_type":"image/png","url":"/models/model-1/reports/false-positives/example.png"}]}"#.utf8
        )
        let client = RecordingAPIClient(responseData: response)
        let service = ModelService(client: client)

        let reports = try await service.reports(modelID: "model-1")
        let item = try #require(reports.first)
        #expect(item.category == "false_positives")
        #expect(item.contentType == "image/png")

        _ = try await service.reportData(item: item)
        #expect(await client.lastRequest?.path == "/models/model-1/reports/false-positives/example.png")
    }
}
