import Foundation
import Observation

@MainActor
@Observable
final class FailureReportsViewModel {
    let model: ModelRecord
    private(set) var sections: [FailureReportSection] = []
    private(set) var isLoading = false
    var isShowingError = false
    var errorMessage = ""

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
            let grouped = Dictionary(grouping: items, by: \.category)
            sections = grouped.map { category, categoryItems in
                FailureReportSection(
                    category: category,
                    items: categoryItems.sorted(by: { $0.path < $1.path })
                )
            }
            .sorted(by: { $0.category < $1.category })
        } catch {
            showError(error.localizedDescription)
        }
    }

    func data(for item: FailureReportItem) async throws -> Data {
        try await service.reportData(item: item)
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
