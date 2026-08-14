import Foundation
@testable import MoneyTrainer

actor MockTrainingService: TrainingServiceProtocol {
    private(set) var startCount = 0
    let jobValue: TrainingJob

    init(job: TrainingJob) {
        jobValue = job
    }

    func jobs() async throws -> [TrainingJob] { [] }
    func job(id: String) async throws -> TrainingJob { jobValue }

    func start(mockMode: Bool) async throws -> TrainingJob {
        startCount += 1
        return jobValue
    }
}
