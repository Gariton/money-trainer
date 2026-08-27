import SwiftUI

struct BoundingBoxAnnotationLabel: View {
    let annotation: Annotation
    let requiresReview: Bool
    let displaySize: CGSize
    let viewportScale: CGFloat
    let placesLabelAbove: Bool

    @State private var intrinsicHeight: CGFloat = 0

    private var inverseViewportScale: CGFloat {
        1.0 / max(viewportScale, 1)
    }

    private var verticalOffset: CGFloat {
        let gap = 2 * inverseViewportScale
        return placesLabelAbove
            ? -(intrinsicHeight * inverseViewportScale + gap)
            : gap
    }

    var body: some View {
        BoundingBoxLabel(annotation: annotation, requiresReview: requiresReview)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                intrinsicHeight = newValue
            }
            .scaleEffect(inverseViewportScale, anchor: .topLeading)
            .frame(
                width: displaySize.width,
                height: displaySize.height,
                alignment: .topLeading
            )
            .offset(y: verticalOffset)
            .allowsHitTesting(false)
    }
}
