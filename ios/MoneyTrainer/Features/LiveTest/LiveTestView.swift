import SwiftUI

struct LiveTestView: View {
    let modelManager: ModelManager
    let datasetService: any DatasetServiceProtocol
    let onOpenModels: () -> Void

    @State private var viewModel = LiveTestViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.controller.hasActiveModel {
                    cameraSurface
                } else {
                    noActiveModelState
                }
            }
            .navigationTitle("実機テスト")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.start(modelManager: modelManager) }
            .onChange(of: modelManager.activeModelID) { _, _ in
                Task { await viewModel.updateModel(modelManager: modelManager) }
            }
            .onDisappear(perform: viewModel.controller.stop)
            .fullScreenCover(item: $viewModel.correctionDraft) { draft in
                AnnotationEditorView(draft: draft, service: datasetService) { }
            }
            .alert("カメラエラー", isPresented: $viewModel.controller.isShowingError) {
                Button("OK", role: .cancel, action: viewModel.controller.clearError)
            } message: {
                Text(viewModel.controller.errorMessage)
            }
        }
    }

    private var cameraSurface: some View {
        LiveCameraOverlayView(viewModel: viewModel)
            .safeAreaInset(edge: .bottom) {
                LiveTestSummaryBar(viewModel: viewModel)
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.error {
                    ErrorBanner(
                        error: error,
                        onDismiss: viewModel.clearError
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label(viewModel.activeModelLabel, systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    /// モデルがないままカメラを回し続けても意味がないので、ここで止めて導線を出す。
    private var noActiveModelState: some View {
        EmptyStateView(
            title: "Activeなモデルがありません",
            systemImage: "shippingbox",
            message: "学習済みモデルを端末へダウンロードして有効化すると、ここで硬貨を数えられます。"
        ) {
            Button("モデルを選ぶ", systemImage: "arrow.right", action: onOpenModels)
                .buttonStyle(.borderedProminent)
        }
        .onAppear(perform: viewModel.controller.stop)
    }
}
