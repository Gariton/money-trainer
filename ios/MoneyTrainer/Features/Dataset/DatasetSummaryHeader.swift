import SwiftUI

/// 数字の羅列をやめ、「次に何をすべきか」を1行の主語として出す要約。
/// 内訳は既定で畳み、画像がすぐ見える高さに収める。
struct DatasetSummaryHeader: View {
    let stats: DatasetStats
    let captureSessionID: String
    let onStartNewSession: () -> Void

    @State private var isShowingBalance = false

    private var target: Int { DesignTokens.trainingReadyImageCount }

    private var headline: String {
        if stats.imageCount == 0 {
            return "まだ画像がありません"
        }
        if stats.unreviewedImageCount > 0 {
            return "未確認 \(stats.unreviewedImageCount)枚"
        }
        if stats.imageCount < target {
            return "学習開始まで あと\(target - stats.imageCount)枚"
        }
        return "学習を開始できます"
    }

    private var headlineTint: Color {
        if stats.imageCount == 0 { return .secondary }
        if stats.unreviewedImageCount > 0 { return .mtWarning }
        return stats.imageCount < target ? .primary : .mtSuccess
    }

    private var counts: [(denomination: CoinDenomination, count: Int)] {
        CoinDenomination.allCases.map {
            ($0, stats.classCounts[$0, default: 0])
        }
    }

    private var balanceSummary: String {
        guard stats.boundingBoxCount > 0,
              let fewest = counts.min(by: { $0.count < $1.count }),
              let most = counts.max(by: { $0.count < $1.count }) else {
            return "金種ごとの内訳はまだありません"
        }
        return "最少 \(fewest.denomination.displayName) \(fewest.count)件 ・ "
            + "最多 \(most.denomination.displayName) \(most.count)件"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.regular) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text(headline)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(headlineTint)

                MeterBar(
                    value: Double(stats.imageCount),
                    total: Double(max(target, stats.imageCount)),
                    tint: stats.imageCount >= target ? .mtSuccess : .mtAccent,
                    target: Double(target)
                )

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            balanceSection

            sessionRow
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.regular)
    }

    private var detailLine: String {
        "画像 \(stats.imageCount) ・ BBox \(stats.boundingBoxCount) ・ "
            + "train \(stats.trainImageCount) / val \(stats.validationImageCount) / test \(stats.testImageCount)"
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Button {
                withAnimation(.snappy) { isShowingBalance.toggle() }
            } label: {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Text(balanceSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isShowingBalance ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("金種ごとの内訳")
            .accessibilityValue(balanceSummary)
            .accessibilityHint(isShowingBalance ? "閉じる" : "開く")

            if isShowingBalance {
                classBalanceRows
            }
        }
    }

    private var classBalanceRows: some View {
        let maximum = max(
            counts.map(\.count).max() ?? 0,
            DesignTokens.balancedInstanceCountPerClass
        )
        return VStack(spacing: DesignTokens.Spacing.compact) {
            ForEach(counts, id: \.denomination) { item in
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Text(item.denomination.displayName)
                        .font(.caption)
                        .frame(width: 44, alignment: .leading)

                    MeterBar(
                        value: Double(item.count),
                        total: Double(maximum),
                        tint: item.count < DesignTokens.balancedInstanceCountPerClass
                            ? .mtWarning
                            : .mtSuccess,
                        target: Double(DesignTokens.balancedInstanceCountPerClass)
                    )

                    Text(item.count, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.denomination.displayName)
                .accessibilityValue("\(item.count)件")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var sessionRow: some View {
        HStack(spacing: DesignTokens.Spacing.compact) {
            Image(systemName: "link")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("セッション \(captureSessionID.prefix(8))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
            Spacer(minLength: 0)
            Button("新しいセッション", action: onStartNewSession)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
        }
        .accessibilityHint("照明・背景・場所を変えたら新しいセッションを開始してください")
    }
}
