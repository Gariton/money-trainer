import Foundation

protocol TrainingServiceProtocol: Sendable {
    func jobs() async throws -> [TrainingJob]
    func job(id: String) async throws -> TrainingJob
    func start(mockMode: Bool) async throws -> TrainingJob
}
