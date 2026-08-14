import SwiftUI

struct BoundingBoxOverlay: View {
    let annotation: Annotation
    let converter: AspectFitCoordinateConverter
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (NormalizedRect, CGSize) -> Void
    let onResize: (NormalizedRect, CGSize) -> Void

    @State private var moveOrigin: NormalizedRect?
    @State private var resizeOrigin: NormalizedRect?

    private var displayRect: CGRect { converter.displayRect(for: annotation.rect) }
    private var requiresReview: Bool {
        annotation.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
    }

    var body: some View {
        Button(action: onSelect) {
            Color.clear
                .contentShape(.rect)
                .overlay(alignment: .topLeading) {
                    BoundingBoxLabel(annotation: annotation, requiresReview: requiresReview)
                        .fixedSize()
                        .offset(y: -2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(
                                width: DesignTokens.minimumTapSize,
                                height: DesignTokens.minimumTapSize
                            )
                            .background(.blue)
                            .clipShape(.circle)
                            .gesture(resizeGesture)
                            .accessibilityLabel("Bounding Boxをリサイズ")
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: displayRect.width, height: displayRect.height)
        .background(.clear)
        .border(
            isSelected ? Color.blue : (requiresReview ? Color.red : Color.yellow),
            width: isSelected ? 3 : DesignTokens.overlayLineWidth
        )
        .position(x: displayRect.midX, y: displayRect.midY)
        .gesture(moveGesture)
        .accessibilityLabel(annotation.denomination.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("選択してドラッグすると移動できます")
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if moveOrigin == nil {
                    moveOrigin = annotation.rect
                    onSelect()
                }
                guard let moveOrigin else { return }
                onMove(moveOrigin, value.translation)
            }
            .onEnded { _ in moveOrigin = nil }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeOrigin == nil { resizeOrigin = annotation.rect }
                guard let resizeOrigin else { return }
                onResize(resizeOrigin, value.translation)
            }
            .onEnded { _ in resizeOrigin = nil }
    }

    private var accessibilityValue: String {
        let confidence = annotation.confidence.map {
            $0.formatted(.percent.precision(.fractionLength(0)))
        } ?? "手動"
        return requiresReview ? "\(confidence)、要確認" : confidence
    }
}
