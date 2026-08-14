import SwiftUI

struct AnnotationCanvasView: View {
    @Bindable var viewModel: AnnotationEditorViewModel
    @State private var canvasSize = CGSize.zero

    var body: some View {
        let converter = AspectFitCoordinateConverter(
            imageSize: viewModel.imageSize,
            canvasSize: canvasSize
        )

        ZStack {
            Color.black

            Image(uiImage: viewModel.image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("アノテーション対象画像")

            ForEach(viewModel.annotations) { annotation in
                BoundingBoxOverlay(
                    annotation: annotation,
                    converter: converter,
                    isSelected: annotation.id == viewModel.selectedAnnotationID,
                    onSelect: { viewModel.select(annotation.id) },
                    onMove: { initial, translation in
                        viewModel.move(
                            id: annotation.id,
                            from: initial,
                            displayTranslation: translation,
                            converter: converter
                        )
                    },
                    onResize: { initial, translation in
                        viewModel.resize(
                            id: annotation.id,
                            from: initial,
                            displayTranslation: translation,
                            converter: converter
                        )
                    }
                )
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            canvasSize = newSize
        }
        .clipped()
    }
}
