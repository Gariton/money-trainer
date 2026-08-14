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
            )
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
}
