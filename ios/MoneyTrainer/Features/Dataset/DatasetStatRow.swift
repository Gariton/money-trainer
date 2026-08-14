import SwiftUI

struct DatasetStatRow: View {
    let title: String
    let value: Int

    var body: some View {
        LabeledContent(title) {
            Text(value, format: .number)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
