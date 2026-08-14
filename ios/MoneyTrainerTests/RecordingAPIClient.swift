import Foundation
@testable import MoneyTrainer

actor RecordingAPIClient: APIClientProtocol {
    private let responseData: Data
    private(set) var lastRequest: APIRequest?

    init(responseData: Data) {
        self.responseData = responseData
    }

    func updateConfiguration(baseURL: URL, token: String?) { }

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as responseType: Response.Type
    ) async throws -> Response {
        lastRequest = request
        return try JSONCoding.makeDecoder().decode(responseType, from: responseData)
    }

    func sendData(_ request: APIRequest) async throws -> Data {
        lastRequest = request
        return responseData
    }
}
