import Foundation
import Observation

@MainActor
@Observable
final class DatasetViewModel {
    private(set) var stats = DatasetStats.empty
    private(set) var images: [DatasetImageRecord] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var informationalMessage: String?
    var isShowingError = false
    var isShowingInformation = false

    @ObservationIgnored private let datasetService: any DatasetServiceProtocol
    @ObservationIgnored private let inferenceService: any InferenceServiceProtocol
    @ObservationIgnored private(set) var captureSessionID = UUID().uuidString

    init(
        datasetService: any DatasetServiceProtocol,
        inferenceService: any InferenceServiceProtocol
    ) {
        self.datasetService = datasetService
        self.inferenceService = inferenceService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedStats = datasetService.stats()
            async let loadedPage = datasetService.images(limit: 50, offset: 0)
            stats = try await loadedStats
            images = try await loadedPage.items
            errorMessage = nil
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func makeDraft(
        imageData: Data,
        source: DatasetSource,
        captureSessionID: String? = nil
    ) async -> AnnotationDraft {
        let sessionID = captureSessionID ?? self.captureSessionID
        do {
            let inference = try await inferenceService.infer(imageData: imageData)
            informationalMessage = inference.modelVersion == nil
                ? "有効なモデルがないため、手動でBounding Boxを追加してください。"
                : nil
            isShowingInformation = informationalMessage != nil
            return AnnotationDraft(
                imageData: imageData,
                source: source,
                captureSessionID: sessionID,
                annotations: inference.annotations,
                modelVersionUsedForPreAnnotation: inference.modelVersion
            )
        } catch {
            informationalMessage = "自動アノテーションに失敗しました。手動編集を続行できます。"
            isShowingInformation = true
            return AnnotationDraft(
                imageData: imageData,
                source: source,
                captureSessionID: sessionID
            )
        }
    }

    func beginNewCaptureSession() {
        captureSessionID = UUID().uuidString
    }

    func presentError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    func clearError() {
        isShowingError = false
        errorMessage = nil
    }

    func clearInformation() {
        isShowingInformation = false
        informationalMessage = nil
    }
}
