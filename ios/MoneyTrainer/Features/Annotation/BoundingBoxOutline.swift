import SwiftUI

struct BoundingBoxOutline: View {
    let annotation: Annotation
    let displaySize: CGSize
    let viewportScale: CGFloat
    let isSelected: Bool
    let requiresReview: Bool
    let overlayColor: Color
    let onSelect: () -> Void
    let onMove: (NormalizedRect, CGSize) -> Void

    @State private var moveOrigin: NormalizedRect?

    private var lineWidth: CGFloat {
        (isSelected ? 3 : DesignTokens.overlayLineWidth) / viewportScale
    }
    private var fillColor: Color {
        isSelected ? overlayColor.opacity(0.12) : .clear
    }
    var body: some View {
        ZStack {
            Rectangle()
                .fill(fillColor)
            Rectangle()
                .strokeBorder(overlayColor, lineWidth: lineWidth)
        }
            .frame(width: displaySize.width, height: displaySize.height)
            .contentShape(.rect)
            .onTapGesture(perform: onSelect)
            .gesture(moveGesture)
            .accessibilityLabel(annotation.denomination.displayName)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("ダブルタップで選択、ドラッグで移動できます")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "選択", onSelect)
    }

    private var moveGesture: some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named(AnnotationCanvasView.coordinateSpaceName)
        )
        .onChanged { value in
            if moveOrigin == nil {
                moveOrigin = annotation.rect
                onSelect()
            }
            guard let moveOrigin else { return }
            onMove(moveOrigin, value.translation)
        }
        .onEnded { _ in
            moveOrigin = nil
        }
    }

    private var accessibilityValue: String {
        let confidence = annotation.confidence.map {
            $0.formatted(.percent.precision(.fractionLength(0)))
        } ?? "手動"
        return requiresReview ? "\(confidence)、要確認" : confidence
    }
}
