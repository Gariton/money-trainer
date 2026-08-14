import SwiftUI

struct LiveCameraOverlayView: View {
    @Bindable var viewModel: LiveTestViewModel
    @State private var canvasSize = CGSize.zero

    var body: some View {
        let converter = AspectFitCoordinateConverter(
            imageSize: viewModel.controller.latestFrameSize,
            canvasSize: canvasSize
        )
        ZStack {
            CameraPreview(session: viewModel.controller.session, gravity: .resizeAspect)
            ForEach(viewModel.controller.detections) { annotation in
                LiveDetectionOverlay(
                    annotation: annotation,
                    converter: converter,
                    isSelected: annotation.id == viewModel.selectedDetectionID,
                    onSelect: { viewModel.select(annotation) }
                )
            }
        }
        .background(.black)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            canvasSize = newSize
        }
        .clipped()
    }
}
