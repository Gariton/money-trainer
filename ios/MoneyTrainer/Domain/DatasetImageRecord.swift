import Foundation

struct DatasetImageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let imageURL: URL?
    let createdAt: Date
    let annotations: [Annotation]
    let source: DatasetSource
    let captureSessionID: String
    let reviewStatus: ReviewStatus
    let modelVersionUsedForPreAnnotation: String?
    let split: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case imageURL = "image_url"
        case createdAt = "created_at"
        case annotations
        case source
        case captureSessionID = "capture_session_id"
        case reviewStatus = "review_status"
        case modelVersionUsedForPreAnnotation = "model_version_used_for_pre_annotation"
        case split
    }
}
