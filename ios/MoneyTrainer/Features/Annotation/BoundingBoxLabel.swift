import SwiftUI

struct BoundingBoxLabel: View {
    let annotation: Annotation
    let requiresReview: Bool

    private var background: Color {
        requiresReview ? .mtDanger : .black.opacity(0.75)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.tight) {
            if annotation.needsReview == true && annotation.confidence == nil {
                Image(systemName: "circle.dashed")
                Text("円形候補")
                    .bold()
            } else {
                Text(annotation.denomination.displayName)
                    .bold()
                    .monospacedDigit()
            }

            if let confidence = annotation.confidence {
                Text(confidence, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .opacity(0.85)
            }

            if requiresReview {
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
        .font(.caption2)
        .padding(.horizontal, DesignTokens.Spacing.compact)
        .padding(.vertical, DesignTokens.Spacing.hairline)
        .foregroundStyle(.white)
        .background(background, in: .capsule)
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
