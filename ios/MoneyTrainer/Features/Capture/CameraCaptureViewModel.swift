@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CameraCaptureViewModel {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var photoProcessor: PhotoCaptureProcessor?

    private(set) var isReady = false
    private(set) var isCapturing = false
    var isShowingError = false
    var errorMessage = ""

    func start() async {
        do {
            try await requestPermission()
            try configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
            isReady = true
        } catch {
            showError(error.localizedDescription)
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isReady = false
    }

    func capture() async -> Data? {
        guard isReady, !isCapturing else { return nil }
        isCapturing = true
        defer {
            isCapturing = false
            photoProcessor = nil
        }
        do {
            let data = try await withCheckedThrowingContinuation { continuation in
                let processor = PhotoCaptureProcessor(continuation: continuation)
                photoProcessor = processor
                let settings: AVCapturePhotoSettings
                if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                settings.flashMode = .off
                photoOutput.capturePhoto(with: settings, delegate: processor)
            }
            return data
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    private func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CameraCaptureError.permissionDenied
            }
        case .denied, .restricted:
            throw CameraCaptureError.permissionDenied
        @unknown default:
            throw CameraCaptureError.permissionDenied
        }
    }

    private func configureIfNeeded() throws {
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraCaptureError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw CameraCaptureError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else { throw CameraCaptureError.cannotAddOutput }
        session.addOutput(photoOutput)
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
