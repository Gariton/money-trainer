import SwiftUI

/// 画面下部の固定ツールバー。選択の有無で行数が変わらないため、
/// キャンバスの高さが操作中に飛ばない。
struct AnnotationToolbar: View {
    @Bindable var viewModel: AnnotationEditorViewModel

    private var statusText: String {
        guard let selected = viewModel.selectedAnnotation else {
            return "Bounding Boxをタップして選択します。画像をダブルタップすると、その位置に追加できます。"
        }
        if selected.confidence == nil && viewModel.selectedRequiresReview {
            return "円形候補です。正しい金種をタップすると確定します。"
        }
        if let confidence = selected.confidence {
            let formatted = confidence.formatted(.percent.precision(.fractionLength(0)))
            return viewModel.selectedRequiresReview
                ? "confidence \(formatted)。低いので金種と位置を確認してください。"
                : "confidence \(formatted)。"
        }
        return "手動で追加したBounding Boxです。"
    }

    private var statusTint: Color {
        guard viewModel.selectedAnnotation != nil else { return .secondary }
        guard viewModel.selectedRequiresReview else { return .secondary }
        return viewModel.selectedAnnotation?.confidence == nil ? .mtWarning : .mtDanger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                Text(viewModel.progressLabel)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Spacer(minLength: 0)

                if viewModel.hasPendingReview {
                    Button(
                        "次の要確認 \(viewModel.pendingReviewCount)",
                        systemImage: "arrow.right.circle.fill",
                        action: viewModel.selectNextNeedingReview
                    )
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if !viewModel.annotations.isEmpty {
                    Label("すべて確認済み", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.mtSuccess)
                }
            }

            CoinDenominationPicker(selection: $viewModel.selectedDenomination) { _ in
                viewModel.confirmSelected()
            }
            .disabled(viewModel.selectedAnnotation == nil)
            .opacity(viewModel.selectedAnnotation == nil ? 0.55 : 1)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusTint)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.top, DesignTokens.Spacing.regular)
        .padding(.bottom, DesignTokens.Spacing.compact)
        .background(.bar)
    }
}
