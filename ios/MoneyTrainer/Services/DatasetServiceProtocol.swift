import Foundation

protocol DatasetServiceProtocol: Sendable {
    func stats() async throws -> DatasetStats
    func images(limit: Int, offset: Int) async throws -> DatasetImagePage
    func image(id: String) async throws -> DatasetImageRecord
    func imageData(id: String) async throws -> Data
    func upload(imageData: Data, metadata: DatasetImageUploadMetadata) async throws -> DatasetImageRecord
    func updateAnnotations(
        imageID: String,
        annotations: [Annotation],
        reviewStatus: ReviewStatus
    ) async throws -> DatasetImageRecord
}
