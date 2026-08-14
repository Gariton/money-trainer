import SwiftUI

struct AnnotationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AnnotationEditorViewModel

    let onSaved: () -> Void

    init(
        draft: AnnotationDraft,
        service: any DatasetServiceProtocol,
        onSaved: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AnnotationEditorViewModel(draft: draft, service: service))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            AnnotationCanvasView(viewModel: viewModel)
                .safeAreaInset(edge: .bottom) {
                    AnnotationInspectorView(viewModel: viewModel)
                }
                .navigationTitle("Annotation Editor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる", systemImage: "xmark", action: dismiss.callAsFunction)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("追加", systemImage: "rectangle.badge.plus", action: viewModel.addAnnotation)
                        Button("削除", systemImage: "trash", role: .destructive, action: viewModel.deleteSelected)
                            .disabled(viewModel.selectedAnnotation == nil)
                        Button("保存", systemImage: "checkmark", action: save)
                            .disabled(viewModel.isSaving)
                    }
                }
                .overlay {
                    if viewModel.isSaving {
                        ProgressView("Datasetへ保存中")
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: DesignTokens.compactCornerRadius))
                    }
                }
                .alert("保存できませんでした", isPresented: $viewModel.isShowingError) {
                    Button("OK", role: .cancel, action: viewModel.clearError)
                } message: {
                    Text(viewModel.errorMessage)
                }
        }
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    private func save() {
        Task {
            guard await viewModel.save() else { return }
            onSaved()
            dismiss()
        }
    }
}
