import SwiftUI

/// カメラを主役にするため、内訳は0件を省いた1行に圧縮する。
/// 修正はこのバーの中で完結させ、ダイアログを挟まない。
struct LiveTestSummaryBar: View {
    @Bindable var viewModel: LiveTestViewModel

    private var breakdown: String {
        let parts = CoinDenomination.allCases.compactMap { denomination -> String? in
            let count = viewModel.count(for: denomination)
            guard count > 0 else { return nil }
            return "\(denomination.displayName)×\(count)"
        }
        return parts.isEmpty ? "検出なし" : parts.joined(separator: "  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.regular) {
                Text(
                    viewModel.total,
                    format: .currency(code: "JPY").precision(.fractionLength(0))
                )
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())

                Text(breakdown)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("合計")
            .accessibilityValue("\(viewModel.total)円、\(breakdown)")

            CoinDenominationPicker(selection: $viewModel.correctionDenomination) { denomination in
                viewModel.correctSelected(to: denomination)
            }
            .disabled(viewModel.selectedDetectionID == nil)
            .opacity(viewModel.selectedDetectionID == nil ? 0.55 : 1)

            Text(
                viewModel.selectedDetectionID == nil
                    ? "検出枠をタップすると、その場で金種を修正できます。"
                    : "正しい金種をタップすると、このFrameをアノテーション画面で開きます。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.top, DesignTokens.Spacing.regular)
        .padding(.bottom, DesignTokens.Spacing.compact)
        .background(.bar)
        .animation(.snappy, value: viewModel.total)
    }
}
