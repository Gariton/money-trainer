import SwiftUI

/// 進行中のJobだけを画面上部で大きく扱う帯。
/// 終わった99件と同じ密度で並べると、いま何が起きているか分からなくなる。
struct ActiveJobBanner: View {
    let job: TrainingJob
    let onOpenDataset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.regular) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                StatusDot(tint: .mtAccent, isPulsing: true)
                Text(job.stageDisplayName)
                    .font(.title3.weight(.bold))
                Spacer(minLength: 0)
                Text(job.normalizedProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            MeterBar(value: job.normalizedProgress, tint: .mtAccent)

            HStack(spacing: DesignTokens.Spacing.compact) {
                Text(job.modelVersion ?? "Job \(job.id.prefix(8))")
                    .monospaced()
                Text("・")
                Text(job.createdAt, style: .relative)
                Text("経過")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !job.validationIssues.isEmpty {
                validationIssues
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mtSurface)
        .animation(.snappy, value: job.normalizedProgress)
        .accessibilityElement(children: .contain)
    }

    private var validationIssues: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            ForEach(job.validationIssues) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.mtWarning)
            }
            // 「何が足りないか」を言うだけでなく、直しに行く導線をその場に置く。
            Button("データセットを確認", systemImage: "photo.stack", action: onOpenDataset)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
