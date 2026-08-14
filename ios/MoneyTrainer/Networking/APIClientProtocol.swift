import Foundation

protocol APIClientProtocol: Sendable {
    func updateConfiguration(baseURL: URL, token: String?) async

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as responseType: Response.Type
    ) async throws -> Response

    func sendData(_ request: APIRequest) async throws -> Data
}
