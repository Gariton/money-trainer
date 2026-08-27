import SwiftUI

/// 失敗の原因と検証エラーをまとめて読むための画面。
struct TrainingJobDetailView: View {
    let job: TrainingJob
    let onOpenDataset: () -> Void

    var body: some View {
        List {
            Section("状態") {
                LabeledContent("ステータス") {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        TrainingStatusIcon(status: job.status)
                        Text(job.status.displayName)
                    }
                }
                LabeledContent("ステージ", value: job.stageDisplayName)
                LabeledContent("進捗") {
                    Text(job.normalizedProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                if let modelVersion = job.modelVersion {
                    LabeledContent("モデル", value: modelVersion)
                }
                LabeledContent("Job ID", value: job.id)
                    .monospaced()
                    .font(.footnote)
            }

            Section("時刻") {
                LabeledContent("作成") {
                    Text(job.createdAt, format: .dateTime.year().month().day().hour().minute())
                }
                if let updatedAt = job.updatedAt {
                    LabeledContent("更新") {
                        Text(updatedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            }

            if let errorMessage = job.errorMessage {
                Section("エラー") {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.mtDanger)
                        .textSelection(.enabled)
                }
            }

            if !job.validationIssues.isEmpty {
                Section {
                    ForEach(job.validationIssues) { issue in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                            Text(issue.message)
                                .font(.footnote)
                            Text(issue.code)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospaced()
                        }
                    }
                    Button("データセットを確認", systemImage: "photo.stack", action: onOpenDataset)
                } header: {
                    Text("Dataset検証")
                } footer: {
                    Text("検証エラーが残っている間、Jobは開始されません。")
                }
            }
        }
        .navigationTitle(job.modelVersion ?? "Job \(job.id.prefix(8))")
        .navigationBarTitleDisplayMode(.inline)
    }
}
