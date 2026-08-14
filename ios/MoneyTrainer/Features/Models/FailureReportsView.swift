import SwiftUI

struct FailureReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FailureReportsViewModel

    init(model: ModelRecord, service: any ModelServiceProtocol) {
        _viewModel = State(initialValue: FailureReportsViewModel(model: model, service: service))
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.sections.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Failure reportがありません",
                        systemImage: "checkmark.circle",
                        description: Text("このモデルでは失敗例が抽出されていません。")
                    )
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
            .navigationTitle("\(viewModel.model.modelVersion) Reports")
            .navigationDestination(for: FailureReportItem.self) { item in
                FailureReportDetailView(item: item) {
                    try await viewModel.data(for: item)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる", systemImage: "xmark", action: dismiss.callAsFunction)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Reportsを読み込み中")
                }
            }
            .task { await viewModel.load() }
            .alert("Report Error", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel, action: viewModel.clearError)
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}
