import SwiftUI

struct FailureReportsView: View {
    @State private var viewModel: FailureReportsViewModel

    init(model: ModelRecord, service: any ModelServiceProtocol) {
        _viewModel = State(initialValue: FailureReportsViewModel(model: model, service: service))
    }

    var body: some View {
        List {
            if viewModel.sections.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    title: "失敗例がありません",
                    systemImage: "checkmark.circle",
                    message: "このモデルでは、誤検出・未検出のサンプルが抽出されていません。"
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                FailureReportRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("失敗例")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: FailureReportItem.self) { item in
            FailureReportDetailView(item: item) {
                try await viewModel.data(for: item)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = viewModel.error {
                ErrorBanner(
                    error: error,
                    onRetry: { Task { await viewModel.load() } },
                    onDismiss: viewModel.clearError
                )
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("失敗例を読み込み中")
            }
        }
        .task { await viewModel.load() }
    }
}
