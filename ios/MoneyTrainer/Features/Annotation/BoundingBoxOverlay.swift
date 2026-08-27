import SwiftUI

struct BoundingBoxOverlay: View {
    let annotation: Annotation
    let converter: AspectFitCoordinateConverter
    let viewportScale: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (NormalizedRect, CGSize) -> Void
    let onResize: (NormalizedRect, BoundingBoxResizeHandle, CGSize) -> Void

    private var displayRect: CGRect { converter.displayRect(for: annotation.rect) }
    private var safeViewportScale: CGFloat { max(viewportScale, 1) }
    private var requiresReview: Bool {
        annotation.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
    }
    private var overlayColor: Color {
        if isSelected { return .blue }
        return requiresReview ? .red : .yellow
    }

    var body: some View {
        ZStack {
            BoundingBoxOutline(
                annotation: annotation,
                displaySize: displayRect.size,
                viewportScale: safeViewportScale,
                isSelected: isSelected,
                requiresReview: requiresReview,
                overlayColor: overlayColor,
                onSelect: onSelect,
                onMove: onMove
            )

            BoundingBoxAnnotationLabel(
                annotation: annotation,
                requiresReview: requiresReview,
                displaySize: displayRect.size,
                viewportScale: safeViewportScale
            )

            if isSelected {
                ForEach(BoundingBoxResizeHandle.allCases) { handle in
                    BoundingBoxResizeControl(
                        annotation: annotation,
                        handle: handle,
                        displaySize: displayRect.size,
                        viewportScale: safeViewportScale,
                        onSelect: onSelect,
                        onResize: onResize
                    )
                }
            }
        }
        .frame(
            width: max(
                displayRect.width + DesignTokens.minimumTapSize / safeViewportScale,
                DesignTokens.minimumTapSize / safeViewportScale
            ),
            height: max(
                displayRect.height + DesignTokens.minimumTapSize / safeViewportScale,
                DesignTokens.minimumTapSize / safeViewportScale
            )
        )
        .position(x: displayRect.midX, y: displayRect.midY)
    }
}
