import Foundation

struct AnnotationUpdateRequest: Encodable, Sendable {
    let annotations: [Annotation]
    let reviewStatus: ReviewStatus
}
