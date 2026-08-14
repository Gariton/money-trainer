@preconcurrency import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: VideoPreviewView, context: Context) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
    }
}
