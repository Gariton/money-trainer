import SwiftUI

struct BoundingBoxOutline: View {
    let annotation: Annotation
    let displaySize: CGSize
    let viewportScale: CGFloat
    let isSelected: Bool
    let requiresReview: Bool
    let overlayColor: Color
    let onSelect: () -> Void
    let onBeginEdit: () -> Void
    let onMove: (NormalizedRect, CGSize) -> Void

    @State private var moveOrigin: NormalizedRect?

    private var lineWidth: CGFloat {
        (isSelected
            ? DesignTokens.selectedOverlayLineWidth
            : DesignTokens.overlayLineWidth) / viewportScale
    }
    private var fillColor: Color {
        isSelected ? overlayColor.opacity(0.12) : .clear
    }
    /// 要確認は色だけでなく破線でも区別する。色覚特性に依存させない。
    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth,
            dash: requiresReview ? [6 / viewportScale, 4 / viewportScale] : []
        )
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fillColor)

            // 明るい背景でも枠が沈まないよう、白の下線を敷いてから色を重ねる。
            Rectangle()
                .stroke(.white.opacity(0.7), lineWidth: lineWidth * 2)
            Rectangle()
                .stroke(overlayColor, style: strokeStyle)
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
                onBeginEdit()
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
