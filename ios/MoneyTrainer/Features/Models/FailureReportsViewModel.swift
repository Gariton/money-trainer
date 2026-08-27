import Foundation
import Observation

@MainActor
@Observable
final class FailureReportsViewModel {
    let model: ModelRecord
    private(set) var sections: [FailureReportSection] = []
    private(set) var isLoading = false
    var error: AppError?

    @ObservationIgnored private let service: any ModelServiceProtocol

    init(model: ModelRecord, service: any ModelServiceProtocol) {
        self.model = model
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await service.reports(modelID: model.id)
            error = nil
            let grouped = Dictionary(grouping: items, by: \.category)
            sections = grouped.map { category, categoryItems in
                FailureReportSection(
                    category: category,
                    items: categoryItems.sorted(by: { $0.path < $1.path })
                )
            }
            .sorted(by: { $0.category < $1.category })
        } catch {
            self.error = AppError(error, title: "失敗例を読み込めません")
        }
    }

    func data(for item: FailureReportItem) async throws -> Data {
        try await service.reportData(item: item)
    }

    func clearError() {
        error = nil
    }
}
