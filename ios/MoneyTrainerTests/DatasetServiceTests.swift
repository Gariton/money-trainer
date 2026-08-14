import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Dataset service multipart contract")
struct DatasetServiceTests {
    @Test("Upload uses server field names and origin coordinates")
    func uploadMultipart() async throws {
        let response = Data(
            #"{"id":"image-1","image_url":"/datasets/images/image-1/content","created_at":"2026-08-14T00:00:00Z","annotations":[],"source":"camera","capture_session_id":"session-1","review_status":"reviewed","model_version_used_for_pre_annotation":null,"split":null}"#.utf8
        )
        let client = RecordingAPIClient(responseData: response)
        let service = DatasetService(client: client)
        _ = try await service.upload(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            metadata: DatasetImageUploadMetadata(
                source: .camera,
                captureSessionID: "session-1",
                reviewStatus: .reviewed,
                annotations: [
                    Annotation(
                        denomination: .ten,
                        rect: NormalizedRect(centerX: 0.3, centerY: 0.4, width: 0.2, height: 0.2)
                    )
                ],
                modelVersionUsedForPreAnnotation: "v3"
            )
        )

        let request = try #require(await client.lastRequest)
        #expect(request.path == "datasets/images")
        #expect(request.method == .post)
        let body = try #require(request.body)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"image\""))
        #expect(text.contains("name=\"capture_session_id\""))
        #expect(text.contains("session-1"))
        #expect(text.contains(#""class":"jpy_10""#))
        #expect(!text.contains(#""id":"#))
    }
}
