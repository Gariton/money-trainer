import Foundation

struct FailureReportList: Codable, Equatable, Sendable {
    let items: [FailureReportItem]
}
