import SwiftUI

struct BoundingBoxLabel: View {
    let annotation: Annotation
    let requiresReview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(annotation.denomination.displayName)
                .bold()
            if let confidence = annotation.confidence {
                Text(confidence, format: .percent.precision(.fractionLength(0)))
            }
            if requiresReview {
                Label("要確認", systemImage: "exclamationmark.triangle.fill")
                    .bold()
            }
        }
        .font(.footnote)
        .padding(4)
        .foregroundStyle(.white)
        .background(requiresReview ? Color.red : Color.black)
        .clipShape(.rect(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }
}
