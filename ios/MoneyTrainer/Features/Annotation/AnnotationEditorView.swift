import SwiftUI

struct AnnotationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AnnotationEditorViewModel
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDiscard = false

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
                    AnnotationToolbar(viewModel: viewModel)
                }
                .safeAreaInset(edge: .top) {
                    if let error = viewModel.error {
                        ErrorBanner(
                            error: error,
                            onRetry: save,
                            onDismiss: viewModel.clearError
                        )
                    }
                }
                .navigationTitle(viewModel.isEditingExistingImage ? "アノテーションを編集" : "アノテーション")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .overlay {
                    if viewModel.isSaving {
                        ProgressView("保存中")
                            .padding(DesignTokens.Spacing.loose)
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: DesignTokens.regularCornerRadius))
                    }
                }
                .confirmationDialog(
                    "このBounding Boxを削除しますか？",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("削除", role: .destructive, action: viewModel.deleteSelected)
                } message: {
                    Text("取り消しボタンで元に戻せます。")
                }
                .confirmationDialog(
                    "編集内容を破棄しますか？",
                    isPresented: $isConfirmingDiscard,
                    titleVisibility: .visible
                ) {
                    Button("破棄して閉じる", role: .destructive, action: dismiss.callAsFunction)
                    Button("編集を続ける", role: .cancel) {}
                }
        }
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.hasUnsavedChanges)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる", systemImage: "xmark", action: close)
                .disabled(viewModel.isSaving)
        }

        // 破壊的操作は左に寄せ、保存とは離して置く。
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("取り消す", systemImage: "arrow.uturn.backward", action: viewModel.undo)
                .disabled(!viewModel.canUndo)

            Menu("編集", systemImage: "ellipsis.circle") {
                Button("Bounding Boxを追加", systemImage: "rectangle.badge.plus") {
                    viewModel.addAnnotation()
                }
                Button("残りをすべて確認済みにする", systemImage: "checkmark.circle") {
                    viewModel.confirmAll()
                }
                .disabled(!viewModel.hasPendingReview)
                Divider()
                Button("選択中のBoxを削除", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .disabled(viewModel.selectedAnnotation == nil)
            }

            Button("保存", systemImage: "checkmark", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving || viewModel.annotations.isEmpty)
        }
    }

    private func close() {
        if viewModel.hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        Task {
            guard await viewModel.save() else { return }
            onSaved()
            dismiss()
        }
    }
}
