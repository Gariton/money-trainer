import Foundation

struct DatasetImageUploadMetadata: Encodable, Sendable {
    let source: DatasetSource
    let captureSessionID: String
    let reviewStatus: ReviewStatus
    let annotations: [Annotation]
    let modelVersionUsedForPreAnnotation: String?
}
