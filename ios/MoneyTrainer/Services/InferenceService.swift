import Foundation

struct InferenceService: InferenceServiceProtocol, Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func infer(imageData: Data) async throws -> InferenceResponse {
        var form = MultipartFormData()
        form.appendFile(name: "image", filename: "inference.jpg", mimeType: "image/jpeg", contents: imageData)
        form.finalize()
        let request = APIRequest(
            path: "inference",
            method: .post,
            headers: ["Content-Type": "multipart/form-data; boundary=\(form.boundary)"],
            body: form.data
        )
        return try await client.send(request, as: InferenceResponse.self)
    }
}
