import Foundation
import Observation

@MainActor
@Observable
final class DatasetViewModel {
    private(set) var stats = DatasetStats.empty
    private(set) var images: [DatasetImageRecord] = []
    private(set) var isLoading = false
    private(set) var isPreparingDraft = false
    private(set) var isOpeningExistingImage = false

    var filter = DatasetFilter.all
    var error: AppError?
    var informationalMessage: String?

    @ObservationIgnored private let datasetService: any DatasetServiceProtocol
    @ObservationIgnored private let inferenceService: any InferenceServiceProtocol
    @ObservationIgnored private let circleDetector: any CoinCircleDetecting
    @ObservationIgnored private(set) var captureSessionID = UUID().uuidString

    init(
        datasetService: any DatasetServiceProtocol,
        inferenceService: any InferenceServiceProtocol,
        circleDetector: any CoinCircleDetecting = CoinCircleDetector()
    ) {
        self.datasetService = datasetService
        self.inferenceService = inferenceService
        self.circleDetector = circleDetector
    }

    var filteredImages: [DatasetImageRecord] {
        images.filter(filter.matches)
    }

    func count(for filter: DatasetFilter) -> Int {
        images.count(where: filter.matches)
    }

    var isPresentingBlockingWork: Bool {
        isPreparingDraft || isOpeningExistingImage
    }

    var blockingWorkMessage: String {
        isOpeningExistingImage ? "画像を読み込み中" : "硬貨候補を検出中"
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedStats = datasetService.stats()
            async let loadedPage = datasetService.images(limit: 50, offset: 0)
            stats = try await loadedStats
            images = try await loadedPage.items
            error = nil
        } catch {
            present(error)
        }
    }

    func makeDraft(
        imageData: Data,
        source: DatasetSource,
        captureSessionID: String? = nil
    ) async -> AnnotationDraft {
        isPreparingDraft = true
        defer { isPreparingDraft = false }
        let sessionID = captureSessionID ?? self.captureSessionID
        async let detectedCircleRects = detectCircleCandidates(in: imageData)

        do {
            let inference = try await inferenceService.infer(imageData: imageData)
            let circleRects = await detectedCircleRects
            let annotations = annotations(
                merging: inference.annotations,
                withCircleRects: circleRects
            )
            let supplementalCount = annotations.count - inference.annotations.count
            informationalMessage = preparationMessage(
                modelVersion: inference.modelVersion,
                supplementalCircleCount: supplementalCount,
                totalAnnotationCount: annotations.count
            )
            return AnnotationDraft(
                imageData: imageData,
                source: source,
                captureSessionID: sessionID,
                annotations: annotations,
                modelVersionUsedForPreAnnotation: inference.modelVersion
            )
        } catch {
            let circleRects = await detectedCircleRects
            let annotations = circleAnnotations(from: circleRects)
            informationalMessage = annotations.isEmpty
                ? "自動アノテーションに失敗しました。手動編集を続行できます。"
                : "モデル推論に失敗したため、端末内で円形候補を\(annotations.count)件追加しました。金種と位置を確認してください。"
            return AnnotationDraft(
                imageData: imageData,
                source: source,
                captureSessionID: sessionID,
                annotations: annotations
            )
        }
    }

    /// 既存のDataset画像を再アノテーションするためのDraftを作る。
    func makeEditorDraft(for record: DatasetImageRecord) async -> AnnotationDraft? {
        isOpeningExistingImage = true
        defer { isOpeningExistingImage = false }
        do {
            let data = try await datasetService.imageData(id: record.id)
            return AnnotationDraft(
                imageData: data,
                source: record.source,
                captureSessionID: record.captureSessionID,
                annotations: record.annotations,
                modelVersionUsedForPreAnnotation: record.modelVersionUsedForPreAnnotation,
                existingImageID: record.id
            )
        } catch {
            present(error)
            return nil
        }
    }

    func beginNewCaptureSession() {
        captureSessionID = UUID().uuidString
    }

    func present(_ error: any Error) {
        self.error = AppError(error)
    }

    func present(message: String, title: String = "処理できませんでした") {
        error = AppError(kind: .validation, title: title, message: message)
    }

    func clearError() {
        error = nil
    }

    func clearInformation() {
        informationalMessage = nil
    }

    private func detectCircleCandidates(in imageData: Data) async -> [NormalizedRect] {
        do {
            return try await circleDetector.detect(in: imageData)
        } catch {
            return []
        }
    }

    private func annotations(
        merging inferredAnnotations: [Annotation],
        withCircleRects circleRects: [NormalizedRect]
    ) -> [Annotation] {
        var annotations = inferredAnnotations

        for rect in circleRects where !annotations.contains(where: {
            $0.rect.intersectionOverUnion(with: rect) >= 0.35
                || $0.rect.intersectionOverSmallerRect(with: rect) >= 0.65
        }) {
            annotations.append(circleAnnotation(for: rect))
        }
        return annotations
    }

    private func circleAnnotations(from rects: [NormalizedRect]) -> [Annotation] {
        rects.map(circleAnnotation)
    }

    private func circleAnnotation(for rect: NormalizedRect) -> Annotation {
        Annotation(
            denomination: .one,
            rect: rect,
            confidence: nil,
            needsReview: true
        )
    }

    private func preparationMessage(
        modelVersion: String?,
        supplementalCircleCount: Int,
        totalAnnotationCount: Int
    ) -> String? {
        if supplementalCircleCount > 0 {
            return "円形候補を\(supplementalCircleCount)件、自動追加しました。金種と位置を確認してください。"
        }
        if modelVersion == nil && totalAnnotationCount == 0 {
            return "硬貨候補を検出できませんでした。必要なBounding Boxを手動で追加してください。"
        }
        return nil
    }
}
