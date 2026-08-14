import SwiftUI

struct PerClassMetricsView: View {
    let metrics: [CoinDenomination: ClassMetrics]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("金種別 metrics", isExpanded: $isExpanded) {
            Grid(alignment: .trailing) {
                GridRow {
                    Text("金種")
                    Text("P")
                    Text("R")
                    Text("AP")
                }
                .bold()

                ForEach(CoinDenomination.allCases) { denomination in
                    if let classMetrics = metrics[denomination] {
                        GridRow {
                            Text(denomination.displayName)
                            Text(classMetrics.precision, format: .percent.precision(.fractionLength(1)))
                            Text(classMetrics.recall, format: .percent.precision(.fractionLength(1)))
                            Text(
                                classMetrics.averagePrecision,
                                format: .percent.precision(.fractionLength(1))
                            )
                        }
                        .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
