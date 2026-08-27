import SwiftUI

struct BoundingBoxResizeControl: View {
    let annotation: Annotation
    let handle: BoundingBoxResizeHandle
    let displaySize: CGSize
    let viewportScale: CGFloat
    let onSelect: () -> Void
    let onResize: (NormalizedRect, BoundingBoxResizeHandle, CGSize) -> Void

    @State private var resizeOrigin: NormalizedRect?

    private var visualSize: CGFloat {
        DesignTokens.resizeHandleSize / viewportScale
    }
    private var hitSize: CGFloat {
        DesignTokens.minimumTapSize / viewportScale
    }
    private var borderWidth: CGFloat {
        3 / viewportScale
    }
    private var handleOffset: CGSize {
        CGSize(
            width: handle.horizontalSign * displaySize.width / 2,
            height: handle.verticalSign * displaySize.height / 2
        )
    }

    var body: some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle()
                    .strokeBorder(.blue, lineWidth: borderWidth)
            }
            .frame(width: visualSize, height: visualSize)
            .frame(width: hitSize, height: hitSize)
            .contentShape(.circle)
            .offset(handleOffset)
            .highPriorityGesture(resizeGesture)
            .accessibilityLabel(handle.accessibilityLabel)
            .accessibilityValue("サイズを調整")
            .accessibilityHint("上下にスワイプして拡大・縮小できます")
            .accessibilityAdjustableAction { direction in
                resizeWithAccessibility(direction: direction)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(AnnotationCanvasView.coordinateSpaceName)
        )
        .onChanged { value in
            if resizeOrigin == nil {
                resizeOrigin = annotation.rect
                onSelect()
            }
            guard let resizeOrigin else { return }
            onResize(resizeOrigin, handle, value.translation)
        }
        .onEnded { _ in
            resizeOrigin = nil
        }
    }

    private func resizeWithAccessibility(direction: AccessibilityAdjustmentDirection) {
        let distance: CGFloat
        switch direction {
        case .increment:
            distance = 8
        case .decrement:
            distance = -8
        @unknown default:
            return
        }
        onResize(annotation.rect, handle, handle.diagonalTranslation(distance: distance))
    }
}
