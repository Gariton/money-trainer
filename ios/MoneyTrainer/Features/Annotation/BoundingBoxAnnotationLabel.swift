import SwiftUI

struct BoundingBoxAnnotationLabel: View {
    let annotation: Annotation
    let requiresReview: Bool
    let displaySize: CGSize
    let viewportScale: CGFloat

    private var inverseViewportScale: CGFloat {
        1.0 / max(viewportScale, 1)
    }
    private var verticalOffset: CGFloat {
        -2.0 / max(viewportScale, 1)
    }

    var body: some View {
        BoundingBoxLabel(annotation: annotation, requiresReview: requiresReview)
            .fixedSize()
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
