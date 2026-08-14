import Foundation
import Testing
@testable import MoneyTrainer

@MainActor
@Suite("Training view model")
struct TrainingViewModelTests {
    @Test("Starts a job and persists it in the visible list")
    func startsJob() async {
        let job = TrainingJob(
            id: "job-1",
            modelVersion: nil,
            status: .queued,
            phase: "dataset_validation",
            progress: 0,
            validationIssues: [],
            errorMessage: nil,
            createdAt: .now,
            updatedAt: nil
        )
        let service = MockTrainingService(job: job)
        let defaults = UserDefaults(suiteName: "TrainingViewModelTests-\(UUID().uuidString)") ?? .standard
        let viewModel = TrainingViewModel(service: service, defaults: defaults)

        await viewModel.startTraining()

        #expect(viewModel.jobs.map(\.id) == ["job-1"])
        #expect(viewModel.activeJobIDs == ["job-1"])
        #expect(await service.startCount == 1)
    }
}
