import SwiftUI

/// パーセントの羅列をやめ、0-100%のスケール上に棒で置く。
/// 基準（有効化中のモデル）は縦線で示し、良し悪しを一目で分かるようにする。
struct ModelMetricsView: View {
    let metrics: ModelMetrics
    let baselineMetrics: ModelMetrics?

    private var rows: [(name: String, value: Double, baseline: Double?)] {
        [
            ("mAP50", metrics.map50, baselineMetrics?.map50),
            ("mAP50–95", metrics.map50To95, baselineMetrics?.map50To95),
            ("Precision", metrics.precision, baselineMetrics?.precision),
            ("Recall", metrics.recall, baselineMetrics?.recall)
        ]
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.regular) {
            ForEach(rows, id: \.name) { row in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        Text(row.name)
                            .font(.footnote)
                        Spacer(minLength: 0)
                        Text(row.value, format: .percent.precision(.fractionLength(1)))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                        if let baseline = row.baseline {
                            difference(row.value - baseline)
                        }
                    }

                    MeterBar(
                        value: row.value,
                        tint: .mtAccent,
                        target: row.baseline
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.name)
                .accessibilityValue(
                    row.value.formatted(.percent.precision(.fractionLength(1)))
                )
            }
        }
    }

    @ViewBuilder
    private func difference(_ value: Double) -> some View {
        if abs(value) < 0.0005 {
            Text("±0.0%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Label {
                Text(
                    value,
                    format: .percent.sign(strategy: .always()).precision(.fractionLength(1))
                )
                .monospacedDigit()
            } icon: {
                Image(systemName: value > 0 ? "arrow.up" : "arrow.down")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(value > 0 ? Color.mtSuccess : Color.mtDanger)
            .accessibilityLabel("有効化中のモデルとの差")
        }
    }
}
