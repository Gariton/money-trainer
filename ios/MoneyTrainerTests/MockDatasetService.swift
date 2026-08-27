import Foundation
@testable import MoneyTrainer

actor MockDatasetService: DatasetServiceProtocol {
    var statsValue: DatasetStats
    var pageValue: DatasetImagePage

    init(stats: DatasetStats = .empty, images: [DatasetImageRecord] = []) {
        statsValue = stats
        pageValue = DatasetImagePage(items: images, total: images.count, limit: 50, offset: 0)
    }

    func stats() async throws -> DatasetStats { statsValue }
    func images(limit: Int, offset: Int) async throws -> DatasetImagePage { pageValue }
    func image(id: String) async throws -> DatasetImageRecord { pageValue.items[0] }
    func imageData(id: String) async throws -> Data { Data() }

    func upload(imageData: Data, metadata: DatasetImageUploadMetadata) async throws -> DatasetImageRecord {
        DatasetImageRecord(
            id: "uploaded",
            imageURL: nil,
            createdAt: .now,
            annotations: metadata.annotations,
            source: metadata.source,
            captureSessionID: metadata.captureSessionID,
            reviewStatus: metadata.reviewStatus,
            modelVersionUsedForPreAnnotation: metadata.modelVersionUsedForPreAnnotation,
            split: nil
        )
    }

    func updateAnnotations(
        imageID: String,
        annotations: [Annotation],
        reviewStatus: ReviewStatus
    ) async throws -> DatasetImageRecord {
        try await image(id: imageID)
    }
}
