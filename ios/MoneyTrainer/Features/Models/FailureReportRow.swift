import SwiftUI

struct FailureReportRow: View {
    let item: FailureReportItem

    private var isImage: Bool { item.contentType.hasPrefix("image/") }

    var body: some View {
        Label {
            Text(item.path)
                .font(.footnote)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.head)
        } icon: {
            Image(systemName: isImage ? "photo" : "doc")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
