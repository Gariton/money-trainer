import Foundation
import Observation

@MainActor
@Observable
final class LiveTestViewModel {
    var controller = LiveTestCameraController()
    let captureSessionID = UUID().uuidString

    var selectedDetectionID: UUID?
    var correctionDraft: AnnotationDraft?
    /// 修正チップの選択状態。選択中の検出に追従させる。
    var correctionDenomination = CoinDenomination.one
    var error: AppError?
    private var activeModelVersion: String?

    func start(modelManager: ModelManager) async {
        await modelManager.load()
        await applyModel(from: modelManager)
    }

    func updateModel(modelManager: ModelManager) async {
        await applyModel(from: modelManager)
    }

    /// Activeモデルがないうちはカメラを構成しない。
    /// 何も検出できない状態でカメラ許可だけ求めるのを避ける。
    private func applyModel(from modelManager: ModelManager) async {
        activeModelVersion = modelManager.localModels
            .first(where: { $0.id == modelManager.activeModelID })?
            .modelVersion
        guard let modelURL = modelManager.activeModelURL else {
            controller.stop()
            await controller.updateModel(at: nil)
            return
        }
        await controller.start(modelURL: modelURL)
    }

    var activeModelLabel: String {
        activeModelVersion.map { "モデル \($0)" } ?? "Activeモデルなし"
    }

    func select(_ annotation: Annotation) {
        selectedDetectionID = annotation.id
        correctionDenomination = annotation.denomination
        Haptics.selection()
    }

    func clearSelection() {
        selectedDetectionID = nil
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
            present(message: "修正するDetectionと現在Frameを取得できませんでした。")
            return
        }
        var annotations = controller.detections
        guard let index = annotations.firstIndex(where: { $0.id == selectedDetectionID }) else {
            present(message: "選択したDetectionが現在Frameにありません。もう一度枠をタップしてください。")
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
        self.selectedDetectionID = nil
    }

    func clearError() {
        error = nil
    }

    private func present(message: String) {
        error = AppError(kind: .validation, title: "修正できませんでした", message: message)
        Haptics.failure()
    }
}
