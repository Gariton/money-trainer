import SwiftUI

/// 履歴は1行1Jobに圧縮する。詳細は別画面へ送る。
struct TrainingJobRow: View {
    let job: TrainingJob

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.regular) {
            TrainingStatusIcon(status: job.status)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                Text(job.modelVersion ?? "Job \(job.id.prefix(8))")
                    .font(.body.weight(.medium))
                    .monospaced()
                Text(job.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(job.status.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainingStatusIcon(status: job.status).tint)
        }
        .accessibilityElement(children: .combine)
    }
}
