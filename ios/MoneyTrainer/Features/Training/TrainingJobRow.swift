import SwiftUI

struct TrainingJobRow: View {
    let job: TrainingJob

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TrainingStatusIcon(status: job.status)
                Text(job.modelVersion ?? "Job \(job.id.prefix(8))")
                    .bold()
                Spacer()
                Text(job.status.displayName)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Stage", value: job.stageDisplayName)

            if !job.status.isTerminal {
                ProgressView(value: job.normalizedProgress) {
                    Text("Progress")
                } currentValueLabel: {
                    Text(job.normalizedProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
            }

            if let errorMessage = job.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            ForEach(job.validationIssues) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(job.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
