import SwiftUI

struct ModelMetricsView: View {
    let metrics: ModelMetrics
    let previousMetrics: ModelMetrics?

    var body: some View {
        VStack(alignment: .leading) {
            Grid(alignment: .leading) {
                metricRow("mAP50", value: metrics.map50, previous: previousMetrics?.map50)
                metricRow("mAP50–95", value: metrics.map50To95, previous: previousMetrics?.map50To95)
                metricRow("Precision", value: metrics.precision, previous: previousMetrics?.precision)
                metricRow("Recall", value: metrics.recall, previous: previousMetrics?.recall)
            }

            if !metrics.perClass.isEmpty {
                PerClassMetricsView(metrics: metrics.perClass)
            }
        }
        .font(.footnote)
    }

    private func metricRow(_ name: String, value: Double, previous: Double?) -> some View {
        GridRow {
            Text(name)
            Text(value, format: .percent.precision(.fractionLength(1)))
                .monospacedDigit()
            if let previous {
                let difference = value - previous
                Text(difference, format: .percent.sign(strategy: .always()).precision(.fractionLength(1)))
                    .monospacedDigit()
                    .foregroundStyle(difference >= 0 ? .green : .red)
                    .accessibilityLabel("前モデルとの差")
            }
        }
    }
}
