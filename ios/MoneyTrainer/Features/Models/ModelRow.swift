import SwiftUI

struct ModelRow: View {
    let model: ModelRecord
    let previousMetrics: ModelMetrics?
    let localModel: LocalModelRecord?
    let isActive: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onActivate: (LocalModelRecord) -> Void
    let onReports: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(model.modelVersion)
                    .font(.headline)
                if isActive {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if localModel != nil {
                    Label("Downloaded", systemImage: "iphone.and.arrow.forward")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.createdAt, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Dataset", value: model.datasetVersion)

            if let metrics = model.metrics {
                ModelMetricsView(metrics: metrics, previousMetrics: previousMetrics)
            }

            if isInstalling {
                ProgressView("Download → Compile → Activate")
            } else if !isActive, let localModel {
                Button("Activate", systemImage: "checkmark.seal", action: { onActivate(localModel) })
                    .buttonStyle(.bordered)
            } else if localModel == nil {
                Button("Download and Activate", systemImage: "arrow.down.circle", action: onInstall)
                    .buttonStyle(.bordered)
                    .disabled(!model.coreMLAvailable)
            }


            Button("Failure Reports", systemImage: "exclamationmark.magnifyingglass", action: onReports)
                .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
    }
}
