@preconcurrency import AVFoundation
import CoreImage
import CoreML
import Observation
import UIKit
@preconcurrency import Vision

@MainActor
@Observable
final class LiveTestCameraController: NSObject {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let videoQueue = DispatchQueue(
        label: "dev.moneytrainer.live-test.video",
        qos: .userInitiated
    )
    @ObservationIgnored nonisolated(unsafe) private var visionRequest: VNCoreMLRequest?
    @ObservationIgnored nonisolated private let ciContext = CIContext(options: [.cacheIntermediates: false])
    @ObservationIgnored nonisolated private let yoloDecoder = YOLOOutputDecoder()

    private(set) var detections: [Annotation] = []
    private(set) var latestFrameData: Data?
    private(set) var latestFrameSize = CGSize(width: 1080, height: 1920)
    private(set) var isReady = false
    private(set) var hasActiveModel = false
    var isShowingError = false
    var errorMessage = ""

    func start(modelURL: URL?) async {
        do {
            try await requestPermission()
            try configureCameraIfNeeded()
            try await configureModel(at: modelURL)
            if !session.isRunning { session.startRunning() }
            isReady = true
        } catch {
            showError(error.localizedDescription)
        }
    }

    func updateModel(at modelURL: URL?) async {
        do {
            try await configureModel(at: modelURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isReady = false
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

    private func configureCameraIfNeeded() throws {
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
        session.sessionPreset = .high
        guard session.canAddInput(input) else { throw CameraCaptureError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(videoOutput) else { throw CameraCaptureError.cannotAddOutput }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)
    }

    private func configureModel(at url: URL?) async throws {
        guard let url else {
            visionRequest = nil
            detections = []
            hasActiveModel = false
            return
        }
        let configuration = MLModelConfiguration()
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        let visionModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        visionRequest = request
        hasActiveModel = true
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

extension LiveTestCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let imageDataAndSize = makeJPEG(from: sampleBuffer)
        let observations: [Annotation]
        if let visionRequest {
            do {
                let handler = VNImageRequestHandler(
                    cmSampleBuffer: sampleBuffer,
                    orientation: .right,
                    options: [:]
                )
                try handler.perform([visionRequest])
                observations = decodeVisionResults(visionRequest.results ?? [])
            } catch {
                observations = []
            }
        } else {
            observations = []
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            detections = observations
            if let imageDataAndSize {
                latestFrameData = imageDataAndSize.data
                latestFrameSize = imageDataAndSize.size
            }
        }
    }

    nonisolated private static func makeAnnotation(
        _ observation: VNRecognizedObjectObservation
    ) -> Annotation? {
        guard let label = observation.labels.first,
              let denomination = CoinDenomination(rawValue: label.identifier) else {
            return nil
        }
        let box = observation.boundingBox
        let upperLeftCenterY = 1 - box.midY
        let confidence = Double(label.confidence)
        return Annotation(
            denomination: denomination,
            rect: NormalizedRect(
                centerX: box.midX,
                centerY: upperLeftCenterY,
                width: box.width,
                height: box.height
            ).clamped(),
            confidence: confidence,
            needsReview: confidence < DesignTokens.lowConfidenceThreshold
        )
    }

    nonisolated private func decodeVisionResults(_ results: [VNObservation]) -> [Annotation] {
        results.flatMap { observation -> [Annotation] in
            if let recognized = observation as? VNRecognizedObjectObservation,
               let annotation = Self.makeAnnotation(recognized) {
                return [annotation]
            }
            if let featureObservation = observation as? VNCoreMLFeatureValueObservation,
               let multiArray = featureObservation.featureValue.multiArrayValue {
                return yoloDecoder.decode(multiArray)
            }
            return []
        }
    }

    nonisolated private func makeJPEG(from sampleBuffer: CMSampleBuffer) -> (data: Data, size: CGSize)? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(orientedImage, from: orientedImage.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.90) else {
            return nil
        }
        return (data, CGSize(width: cgImage.width, height: cgImage.height))
    }
}
