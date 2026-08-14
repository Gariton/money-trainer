import Foundation
import Testing
@testable import MoneyTrainer

@Suite("API request construction")
struct APIRequestBuilderTests {
    @Test("Builds path, query and bearer authorization")
    func buildsAuthenticatedRequest() throws {
        let apiRequest = APIRequest(
            path: "/datasets/images",
            queryItems: [URLQueryItem(name: "limit", value: "20")]
        )
        let request = try APIRequestBuilder().build(
            apiRequest,
            baseURL: try #require(URL(string: "http://localhost:8000")),
            token: "test-token"
        )

        #expect(request.url?.path == "/datasets/images")
        #expect(request.url?.query == "limit=20")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.httpMethod == "GET")
    }
}
