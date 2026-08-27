import SwiftUI

struct LiveDetectionOverlay: View {
    let annotation: Annotation
    let converter: AspectFitCoordinateConverter
    let isSelected: Bool
    let onSelect: () -> Void

    private var requiresReview: Bool {
        annotation.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
    }

    private var tint: Color {
        if isSelected { return .mtAccent }
        return requiresReview ? .mtDanger : .mtWarning
    }

    var body: some View {
        let displayRect = converter.displayRect(for: annotation.rect)
        Button(action: onSelect) {
            ZStack {
                Color.clear
                    .contentShape(.rect)

                // 屋外でも枠が背景に沈まないよう、白の下線に色を重ねる。
                Rectangle()
                    .stroke(.white.opacity(0.75), lineWidth: isSelected ? 5 : 4)
                Rectangle()
                    .stroke(
                        tint,
                        style: StrokeStyle(
                            lineWidth: isSelected
                                ? DesignTokens.selectedOverlayLineWidth
                                : DesignTokens.overlayLineWidth,
                            dash: requiresReview ? [6, 4] : []
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                BoundingBoxLabel(annotation: annotation, requiresReview: requiresReview)
                    .fixedSize()
                    .offset(y: -6)
            }
        }
        .buttonStyle(.plain)
        .frame(width: displayRect.width, height: displayRect.height)
        .position(x: displayRect.midX, y: displayRect.midY)
        .accessibilityLabel(annotation.denomination.displayName)
        .accessibilityValue(
            annotation.confidence?.formatted(.percent.precision(.fractionLength(0))) ?? ""
        )
        .accessibilityHint("選択すると金種を修正できます")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
