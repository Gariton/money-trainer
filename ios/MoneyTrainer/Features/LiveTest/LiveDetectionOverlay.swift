import SwiftUI

struct LiveDetectionOverlay: View {
    let annotation: Annotation
    let converter: AspectFitCoordinateConverter
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let displayRect = converter.displayRect(for: annotation.rect)
        Button(action: onSelect) {
            Color.clear
                .contentShape(.rect)
                .overlay(alignment: .topLeading) {
                    BoundingBoxLabel(
                        annotation: annotation,
                        requiresReview: annotation.requiresReview(
                            threshold: DesignTokens.lowConfidenceThreshold
                        )
                    )
                    .fixedSize()
                }
        }
        .buttonStyle(.plain)
        .frame(width: displayRect.width, height: displayRect.height)
        .border(isSelected ? Color.blue : Color.yellow, width: isSelected ? 3 : 2)
        .position(x: displayRect.midX, y: displayRect.midY)
        .accessibilityLabel(annotation.denomination.displayName)
        .accessibilityValue(
            annotation.confidence?.formatted(.percent.precision(.fractionLength(0))) ?? ""
        )
        .accessibilityHint("選択するとDetectionを修正できます")
    }
}
