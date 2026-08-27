import Foundation
import Testing
@testable import MoneyTrainer

@MainActor
@Suite("Dataset view model")
struct DatasetViewModelTests {
    @Test("Loads stats and carries pre-annotation model version into a draft")
    func loadAndDraft() async {
        let stats = DatasetStats(
            imageCount: 2,
            boundingBoxCount: 3,
            classCounts: [.one: 3],
            trainImageCount: 1,
            validationImageCount: 1,
            testImageCount: 0,
            unreviewedImageCount: 0,
            annotatedImageCount: 2
        )
        let annotation = Annotation(denomination: .one, rect: .centeredDefault, confidence: 0.9)
        let viewModel = DatasetViewModel(
            datasetService: MockDatasetService(stats: stats),
            inferenceService: MockInferenceService(
                response: InferenceResponse(
                    modelID: "model-2",
                    modelVersion: "v2",
                    annotations: [annotation]
                )
            ),
            circleDetector: MockCoinCircleDetector(rects: [])
        )

        await viewModel.load()
        let initialSessionID = viewModel.captureSessionID
        let draft = await viewModel.makeDraft(imageData: Data([1]), source: .photoLibrary)

        #expect(viewModel.stats.imageCount == 2)
        #expect(draft.annotations.count == 1)
        #expect(draft.modelVersionUsedForPreAnnotation == "v2")
        #expect(draft.captureSessionID == initialSessionID)

        viewModel.beginNewCaptureSession()
        #expect(viewModel.captureSessionID != initialSessionID)
    }

    @Test("Uses local circle candidates when no trained model is available")
    func localCircleFallback() async {
        let circleRects = [
            NormalizedRect(centerX: 0.25, centerY: 0.25, width: 0.18, height: 0.18),
            NormalizedRect(centerX: 0.70, centerY: 0.65, width: 0.22, height: 0.22)
        ]
        let viewModel = DatasetViewModel(
            datasetService: MockDatasetService(),
            inferenceService: MockInferenceService(
                response: InferenceResponse(
                    modelID: nil,
                    modelVersion: nil,
                    annotations: []
                )
            ),
            circleDetector: MockCoinCircleDetector(rects: circleRects)
        )

        let draft = await viewModel.makeDraft(imageData: Data([1]), source: .camera)

        #expect(draft.annotations.count == 2)
        #expect(draft.annotations.allSatisfy { $0.needsReview == true })
        #expect(draft.annotations.allSatisfy { $0.confidence == nil })
        #expect(viewModel.informationalMessage?.contains("2件") == true)
        #expect(!viewModel.isPreparingDraft)
    }

    @Test("Adds only circle candidates not already covered by model inference")
    func supplementsModelInferenceWithoutDuplicates() async {
        let inferredRect = NormalizedRect(
            centerX: 0.25,
            centerY: 0.25,
            width: 0.2,
            height: 0.2
        )
        let inferredAnnotation = Annotation(
            denomination: .oneHundred,
            rect: inferredRect,
            confidence: 0.94
        )
        let additionalRect = NormalizedRect(
            centerX: 0.75,
            centerY: 0.7,
            width: 0.18,
            height: 0.18
        )
        let viewModel = DatasetViewModel(
            datasetService: MockDatasetService(),
            inferenceService: MockInferenceService(
                response: InferenceResponse(
                    modelID: "model-3",
                    modelVersion: "v3",
                    annotations: [inferredAnnotation]
                )
            ),
            circleDetector: MockCoinCircleDetector(rects: [inferredRect, additionalRect])
        )

        let draft = await viewModel.makeDraft(imageData: Data([1]), source: .photoLibrary)

        #expect(draft.annotations.count == 2)
        #expect(draft.annotations.first == inferredAnnotation)
        #expect(draft.annotations.last?.rect == additionalRect)
        #expect(draft.annotations.last?.needsReview == true)
        #expect(draft.modelVersionUsedForPreAnnotation == "v3")
    }
}
