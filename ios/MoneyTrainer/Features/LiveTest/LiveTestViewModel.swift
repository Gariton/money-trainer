import Foundation
import Observation

@MainActor
@Observable
final class LiveTestViewModel {
    var controller = LiveTestCameraController()
    let captureSessionID = UUID().uuidString

    var selectedDetectionID: UUID?
    var correctionDraft: AnnotationDraft?
    var isShowingCorrectionMenu = false
    var isShowingError = false
    var errorMessage = ""
    private var activeModelVersion: String?

    func start(modelManager: ModelManager) async {
        await modelManager.load()
        activeModelVersion = modelManager.localModels
            .first(where: { $0.id == modelManager.activeModelID })?
            .modelVersion
        await controller.start(modelURL: modelManager.activeModelURL)
    }

    func updateModel(modelManager: ModelManager) async {
        activeModelVersion = modelManager.localModels
            .first(where: { $0.id == modelManager.activeModelID })?
            .modelVersion
        await controller.updateModel(at: modelManager.activeModelURL)
    }

    func select(_ annotation: Annotation) {
        selectedDetectionID = annotation.id
    }

    func count(for denomination: CoinDenomination) -> Int {
        controller.detections.count(where: { $0.denomination == denomination })
    }

    var total: Int {
        controller.detections.reduce(0) { $0 + $1.denomination.value }
    }

    func correctSelected(to denomination: CoinDenomination) {
        guard let selectedDetectionID,
              let imageData = controller.latestFrameData else {
            showError("修正するDetectionと現在Frameを取得できませんでした。")
            return
        }
        var annotations = controller.detections
        guard let index = annotations.firstIndex(where: { $0.id == selectedDetectionID }) else {
            showError("選択したDetectionが現在Frameにありません。")
            return
        }
        annotations[index].denomination = denomination
        annotations[index].confidence = nil
        annotations[index].needsReview = false
        correctionDraft = AnnotationDraft(
            imageData: imageData,
            source: .liveTest,
            captureSessionID: captureSessionID,
            annotations: annotations,
            modelVersionUsedForPreAnnotation: activeModelVersion
        )
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
