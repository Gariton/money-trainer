import SwiftUI

struct ModelsView: View {
    @Bindable var viewModel: ModelsViewModel

    @Environment(ConnectionMonitor.self) private var connection
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ActiveModelHeader(
                        model: viewModel.activeModel,
                        localModel: viewModel.manager.activeLocalModel
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("すべてのモデル") {
                    if viewModel.models.isEmpty && !viewModel.isLoading {
                        EmptyStateView(
                            title: "モデルがありません",
                            systemImage: "shippingbox",
                            message: "学習が完了すると、ここにモデルが並びます。"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.models) { model in
                            NavigationLink {
                                ModelDetailView(
                                    model: model,
                                    baselineMetrics: viewModel.baselineMetrics,
                                    localModel: viewModel.manager.localModel(id: model.id),
                                    isActive: viewModel.manager.activeModelID == model.id,
                                    installPhase: viewModel.manager.installPhase(for: model.id),
                                    reportService: viewModel.reportService,
                                    onInstall: { install(model) },
                                    onActivate: activate
                                )
                            } label: {
                                ModelRow(
                                    model: model,
                                    isActive: viewModel.manager.activeModelID == model.id,
                                    isDownloaded: viewModel.manager.localModel(id: model.id) != nil,
                                    installPhase: viewModel.manager.installPhase(for: model.id)
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("モデル")
            .refreshable { await viewModel.refresh() }
            .safeAreaInset(edge: .top, spacing: 0) { banners }
            .overlay {
                if viewModel.isLoading && viewModel.models.isEmpty {
                    ProgressView("モデルを読み込み中")
                }
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.manager.error) { _, newValue in
                guard let newValue else { return }
                connection.noteFailure(newValue)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 0) {
            // 同じ原因を二重に出さない。画面固有のエラーがあるときはそちらだけ見せる。
            if viewModel.manager.error == nil {
                ConnectionBanner(monitor: connection) { openSettings() }
            }

            if let error = viewModel.manager.error {
                ErrorBanner(
                    error: error,
                    onRetry: { Task { await viewModel.refresh() } },
                    onOpenSettings: { openSettings() },
                    onDismiss: viewModel.manager.clearError
                )
            }
        }
    }

    private func install(_ model: ModelRecord) {
        Task { await viewModel.install(model) }
    }

    private func activate(_ local: LocalModelRecord) {
        Task { await viewModel.activate(local) }
    }
}
