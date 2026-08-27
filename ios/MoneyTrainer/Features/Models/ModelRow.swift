import SwiftUI

/// 一覧の行は3要素まで。ボタンも指標表もここには置かない。
struct ModelRow: View {
    let model: ModelRecord
    let isActive: Bool
    let isDownloaded: Bool
    let installPhase: ModelManager.InstallPhase?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.regular) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Text(model.modelVersion)
                        .font(.body.weight(.medium))
                        .monospaced()
                    statusBadge
                }
                Text(model.createdAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let metrics = model.metrics {
                VStack(alignment: .trailing, spacing: DesignTokens.Spacing.hairline) {
                    Text(metrics.map50To95, format: .percent.precision(.fractionLength(1)))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Text("mAP50–95")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let installPhase {
            Label(installPhase.displayName, systemImage: "arrow.down.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.mtAccent)
        } else if isActive {
            Label("使用中", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.mtSuccess)
        } else if isDownloaded {
            Label("端末内", systemImage: "iphone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if !model.coreMLAvailable {
            Label("Core ML未出力", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
