import Foundation

struct FailureReportSection: Identifiable, Equatable, Sendable {
    let category: String
    let items: [FailureReportItem]

    var id: String { category }
    var title: String { category.replacing("_", with: " ").capitalized }
}
