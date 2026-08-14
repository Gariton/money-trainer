@preconcurrency import AVFoundation
import Foundation

final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<Data, any Error>

    init(continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CameraCaptureError.invalidPhotoData)
            return
        }
        continuation.resume(returning: data)
    }
}
