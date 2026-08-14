import Foundation

struct TrainingService: TrainingServiceProtocol, Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func jobs() async throws -> [TrainingJob] {
        let page = try await client.send(APIRequest(path: "training/jobs"), as: TrainingJobPage.self)
        return page.items
    }

    func job(id: String) async throws -> TrainingJob {
        try await client.send(APIRequest(path: "training/jobs/\(id)"), as: TrainingJob.self)
    }

    func start(mockMode: Bool) async throws -> TrainingJob {
        let payload = TrainingStartRequest(trainingConfig: nil, mockMode: mockMode)
        let request = APIRequest(
            path: "training/jobs",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: try JSONCoding.encode(payload)
        )
        return try await client.send(request, as: TrainingJob.self)
    }
}
