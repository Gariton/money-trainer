import SwiftUI

struct FailureReportRow: View {
    let item: FailureReportItem

    var body: some View {
        LabeledContent {
            Image(systemName: "chevron.forward")
                .foregroundStyle(.tertiary)
        } label: {
            Label(item.path, systemImage: item.contentType.hasPrefix("image/") ? "photo" : "doc")
        }
        .accessibilityElement(children: .combine)
    }
}
