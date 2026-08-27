import SwiftUI

struct AnnotationCanvasView: View {
    static let coordinateSpaceName = "annotationCanvas"

    @Bindable var viewModel: AnnotationEditorViewModel

    @State private var canvasSize = CGSize.zero
    @State private var viewportScale: CGFloat = DesignTokens.minimumAnnotationZoom
    @State private var viewportOffset = CGSize.zero
    @State private var panOriginOffset: CGSize?
    @State private var magnificationOriginScale: CGFloat?
    @State private var magnificationOriginOffset = CGSize.zero

    var body: some View {
        let converter = AspectFitCoordinateConverter(
            imageSize: viewModel.imageSize,
            canvasSize: canvasSize
        )

        ZStack {
            Color.black

            ZStack {
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(panGesture(converter: converter))

                Image(uiImage: viewModel.image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
                    .accessibilityLabel("アノテーション対象画像")

                ForEach(viewModel.annotations) { annotation in
                    BoundingBoxOverlay(
                        annotation: annotation,
                        converter: converter,
                        viewportScale: viewportScale,
                        isSelected: annotation.id == viewModel.selectedAnnotationID,
                        onSelect: { viewModel.select(annotation.id) },
                        onMove: { initial, translation in
                            viewModel.move(
                                id: annotation.id,
                                from: initial,
                                displayTranslation: translation,
                                viewportScale: viewportScale,
                                converter: converter
                            )
                        },
                        onResize: { initial, handle, translation in
                            viewModel.resize(
                                id: annotation.id,
                                from: initial,
                                at: handle,
                                displayTranslation: translation,
                                viewportScale: viewportScale,
                                converter: converter
                            )
                        }
                    )
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(viewportScale)
            .offset(viewportOffset)
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        .simultaneousGesture(magnificationGesture(converter: converter))
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            canvasSize = newSize
            let updatedConverter = AspectFitCoordinateConverter(
                imageSize: viewModel.imageSize,
                canvasSize: newSize
            )
            viewportOffset = boundedOffset(
                viewportOffset,
                scale: viewportScale,
                converter: updatedConverter
            )
        }
        .overlay(alignment: .topTrailing) {
            AnnotationZoomControls(
                scale: viewportScale,
                onZoomOut: {
                    setViewportScale(
                        viewportScale - DesignTokens.annotationZoomStep,
                        converter: converter
                    )
                },
                onReset: resetViewport,
                onZoomIn: {
                    setViewportScale(
                        viewportScale + DesignTokens.annotationZoomStep,
                        converter: converter
                    )
                }
            )
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            Label("ピンチで拡大・背景ドラッグで移動", systemImage: "hand.pinch")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(12)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedAnnotationID)
        .clipped()
    }

    private func panGesture(converter: AspectFitCoordinateConverter) -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(Self.coordinateSpaceName)
        )
        .onChanged { value in
            guard viewportScale > DesignTokens.minimumAnnotationZoom else { return }
            if panOriginOffset == nil {
                panOriginOffset = viewportOffset
            }
            guard let panOriginOffset else { return }
            let proposedOffset = CGSize(
                width: panOriginOffset.width + value.translation.width,
                height: panOriginOffset.height + value.translation.height
            )
            viewportOffset = boundedOffset(
                proposedOffset,
                scale: viewportScale,
                converter: converter
            )
        }
        .onEnded { _ in
            panOriginOffset = nil
        }
    }

    private func magnificationGesture(
        converter: AspectFitCoordinateConverter
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if magnificationOriginScale == nil {
                    magnificationOriginScale = viewportScale
                    magnificationOriginOffset = viewportOffset
                }
                guard let magnificationOriginScale else { return }

                let proposedScale = magnificationOriginScale * value.magnification
                let nextScale = min(
                    max(proposedScale, DesignTokens.minimumAnnotationZoom),
                    DesignTokens.maximumAnnotationZoom
                )
                let anchor = CGSize(
                    width: (value.startAnchor.x - 0.5) * canvasSize.width,
                    height: (value.startAnchor.y - 0.5) * canvasSize.height
                )
                let scaleDelta = nextScale - magnificationOriginScale
                let proposedOffset = CGSize(
                    width: magnificationOriginOffset.width - anchor.width * scaleDelta,
                    height: magnificationOriginOffset.height - anchor.height * scaleDelta
                )

                viewportScale = nextScale
                viewportOffset = boundedOffset(
                    proposedOffset,
                    scale: nextScale,
                    converter: converter
                )
            }
            .onEnded { _ in
                magnificationOriginScale = nil
                if viewportScale <= DesignTokens.minimumAnnotationZoom + 0.01 {
                    resetViewport()
                } else {
                    viewportOffset = boundedOffset(
                        viewportOffset,
                        scale: viewportScale,
                        converter: converter
                    )
                }
            }
    }

    private func setViewportScale(
        _ proposedScale: CGFloat,
        converter: AspectFitCoordinateConverter
    ) {
        let nextScale = min(
            max(proposedScale, DesignTokens.minimumAnnotationZoom),
            DesignTokens.maximumAnnotationZoom
        )
        withAnimation(.snappy) {
            viewportScale = nextScale
            viewportOffset = boundedOffset(
                viewportOffset,
                scale: nextScale,
                converter: converter
            )
            if nextScale == DesignTokens.minimumAnnotationZoom {
                viewportOffset = .zero
            }
        }
    }

    private func resetViewport() {
        withAnimation(.snappy) {
            viewportScale = DesignTokens.minimumAnnotationZoom
            viewportOffset = .zero
        }
    }

    private func boundedOffset(
        _ proposedOffset: CGSize,
        scale: CGFloat,
        converter: AspectFitCoordinateConverter
    ) -> CGSize {
        let imageFrame = converter.imageFrame
        let maximumX = max(0, (imageFrame.width * scale - canvasSize.width) / 2)
        let maximumY = max(0, (imageFrame.height * scale - canvasSize.height) / 2)
        return CGSize(
            width: min(max(proposedOffset.width, -maximumX), maximumX),
            height: min(max(proposedOffset.height, -maximumY), maximumY)
        )
    }
}
