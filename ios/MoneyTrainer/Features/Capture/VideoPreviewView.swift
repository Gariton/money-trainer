@preconcurrency import AVFoundation
import UIKit

final class VideoPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("VideoPreviewView requires AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
