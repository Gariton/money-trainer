import SwiftUI

struct DatasetImageRow: View {
    let image: DatasetImageRecord

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent {
                Text(image.annotations.count, format: .number)
                    .monospacedDigit()
            } label: {
                Label(image.source.displayName, systemImage: "photo")
            }

            HStack {
                Text(image.createdAt, format: .dateTime.month().day().hour().minute())
                Spacer()
                Text(image.reviewStatus == .reviewed ? "Reviewed" : "Needs review")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
