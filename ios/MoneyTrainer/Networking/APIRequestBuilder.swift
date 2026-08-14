import Foundation

struct APIRequestBuilder: Sendable {
    func build(_ apiRequest: APIRequest, baseURL: URL, token: String?) throws -> URLRequest {
        let normalizedPath = apiRequest.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointURL = baseURL.appending(path: normalizedPath)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }
        if !apiRequest.queryItems.isEmpty {
            components.queryItems = apiRequest.queryItems
        }
        guard let url = components.url else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method.rawValue
        request.httpBody = apiRequest.body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in apiRequest.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
