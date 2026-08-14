import Foundation

struct ModelService: ModelServiceProtocol, Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func models() async throws -> [ModelRecord] {
        let page = try await client.send(APIRequest(path: "models"), as: ModelPage.self)
        return page.items
    }

    func latest() async throws -> ModelRecord {
        try await client.send(APIRequest(path: "models/latest"), as: ModelRecord.self)
    }

    func model(id: String) async throws -> ModelRecord {
        try await client.send(APIRequest(path: "models/\(id)"), as: ModelRecord.self)
    }

    func download(id: String) async throws -> Data {
        try await client.sendData(APIRequest(path: "models/\(id)/download"))
    }

    func reports(modelID: String) async throws -> [FailureReportItem] {
        let response = try await client.send(
            APIRequest(path: "models/\(modelID)/reports"),
            as: FailureReportList.self
        )
        return response.items
    }

    func reportData(item: FailureReportItem) async throws -> Data {
        try await client.sendData(APIRequest(path: item.url))
    }
}
