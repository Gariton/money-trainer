import SwiftUI

struct LiveTestView: View {
    let modelManager: ModelManager
    let datasetService: any DatasetServiceProtocol

    @State private var viewModel = LiveTestViewModel()

    var body: some View {
        NavigationStack {
            LiveCameraOverlayView(viewModel: viewModel)
                .safeAreaInset(edge: .bottom) {
                    CoinCountSummaryView(viewModel: viewModel, correctAction: showCorrectionMenu)
                }
                .navigationTitle("Live Test")
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .top) {
                    if !viewModel.controller.hasActiveModel {
                        Label("Activeモデルなし", systemImage: "exclamationmark.triangle.fill")
                            .padding(8)
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: DesignTokens.compactCornerRadius))
                            .padding()
                    }
                }
                .task { await viewModel.start(modelManager: modelManager) }
                .onChange(of: modelManager.activeModelID) { _, _ in
                    Task { await viewModel.updateModel(modelManager: modelManager) }
                }
                .onDisappear(perform: viewModel.controller.stop)
                .confirmationDialog(
                    "Correct Detection",
                    isPresented: $viewModel.isShowingCorrectionMenu,
                    titleVisibility: .visible
                ) {
                    ForEach(CoinDenomination.allCases) { denomination in
                        Button(denomination.displayName) {
                            viewModel.correctSelected(to: denomination)
                        }
                    }
                } message: {
                    Text("正しい金種を選ぶと、このFrameをAnnotation Editorで確認できます。")
                }
                .fullScreenCover(item: $viewModel.correctionDraft) { draft in
                    AnnotationEditorView(draft: draft, service: datasetService) { }
                }
                .alert("Live Test Error", isPresented: $viewModel.isShowingError) {
                    Button("OK", role: .cancel, action: viewModel.clearError)
                } message: {
                    Text(viewModel.errorMessage)
                }
                .alert("Camera Error", isPresented: $viewModel.controller.isShowingError) {
                    Button("OK", role: .cancel, action: viewModel.controller.clearError)
                } message: {
                    Text(viewModel.controller.errorMessage)
                }
        }
    }

    private func showCorrectionMenu() {
        viewModel.isShowingCorrectionMenu = true
    }
}
