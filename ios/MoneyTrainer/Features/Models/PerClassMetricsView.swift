import SwiftUI

/// 金種ごとの指標。DisclosureGroupの入れ子をやめ、素直な表にする。
struct PerClassMetricsView: View {
    let metrics: [CoinDenomination: ClassMetrics]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: DesignTokens.Spacing.comfortable) {
            GridRow {
                Text("金種")
                    .gridColumnAlignment(.leading)
                Text("P")
                Text("R")
                Text("AP")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            ForEach(CoinDenomination.allCases) { denomination in
                if let classMetrics = metrics[denomination] {
                    GridRow {
                        Text(denomination.displayName)
                            .gridColumnAlignment(.leading)
                        Text(classMetrics.precision, format: percentFormat)
                        Text(classMetrics.recall, format: percentFormat)
                        Text(classMetrics.averagePrecision, format: percentFormat)
                            .foregroundStyle(
                                classMetrics.averagePrecision < 0.5
                                    ? Color.mtWarning
                                    : Color.primary
                            )
                    }
                    .font(.footnote)
                    .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var percentFormat: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(1))
    }
}
