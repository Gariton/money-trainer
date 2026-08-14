import SwiftUI

struct ModelsView: View {
    @Bindable var viewModel: ModelsViewModel
    @State private var reportsModel: ModelRecord?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.models.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "モデルがありません",
                        systemImage: "shippingbox",
                        description: Text("Training完了後にモデルが表示されます。")
                    )
                } else {
                    ForEach(viewModel.models.enumerated(), id: \.element.id) { index, model in
                        ModelRow(
                            model: model,
                            previousMetrics: previousMetrics(after: index),
                            localModel: viewModel.manager.localModel(id: model.id),
                            isActive: viewModel.manager.activeModelID == model.id,
                            isInstalling: viewModel.manager.installingModelIDs.contains(model.id),
                            onInstall: { install(model) },
                            onActivate: activate,
                            onReports: { reportsModel = model }
                        )
                    }
                }
            }
            .navigationTitle("Models")
            .refreshable { await viewModel.refresh() }
            .overlay {
                if viewModel.isLoading && viewModel.models.isEmpty {
                    ProgressView("モデルを読み込み中")
                }
            }
            .task { await viewModel.load() }
            .alert("Model Error", isPresented: $viewModel.manager.isShowingError) {
                Button("OK", role: .cancel, action: viewModel.manager.clearError)
            } message: {
                Text(viewModel.manager.errorMessage)
            }
            .sheet(item: $reportsModel) { model in
                FailureReportsView(model: model, service: viewModel.reportService)
            }
        }
    }

    private func previousMetrics(after index: Int) -> ModelMetrics? {
        guard viewModel.models.indices.contains(index + 1) else { return nil }
        return viewModel.models[index + 1].metrics
    }

    private func install(_ model: ModelRecord) {
        Task { await viewModel.install(model) }
    }

    private func activate(_ local: LocalModelRecord) {
        Task { await viewModel.activate(local) }
    }
}
