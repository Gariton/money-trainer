import Foundation

enum ReviewStatus: String, Codable, Sendable {
    case unreviewed
    case reviewed
    case needsReview = "needs_review"
}
