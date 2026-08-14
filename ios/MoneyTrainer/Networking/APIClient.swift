import Foundation

actor APIClient: APIClientProtocol {
    private var baseURL: URL
    private var token: String?
    private let session: URLSession
    private let requestBuilder: APIRequestBuilder

    init(
        baseURL: URL,
        token: String?,
        session: URLSession = .shared,
        requestBuilder: APIRequestBuilder = APIRequestBuilder()
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.requestBuilder = requestBuilder
    }

    func updateConfiguration(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as responseType: Response.Type
    ) async throws -> Response {
        let data = try await sendData(request)
        do {
            return try JSONCoding.makeDecoder().decode(responseType, from: data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func sendData(_ request: APIRequest) async throws -> Data {
        let urlRequest = try requestBuilder.build(request, baseURL: baseURL, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONCoding.makeDecoder().decode(ServerErrorPayload.self, from: data)
            let fallback = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIError.server(
                statusCode: httpResponse.statusCode,
                message: payload?.detail ?? payload?.message ?? fallback
            )
        }
        return data
    }
}
