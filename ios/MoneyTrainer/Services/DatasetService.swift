import Foundation

struct DatasetService: DatasetServiceProtocol, Sendable {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func stats() async throws -> DatasetStats {
        try await client.send(APIRequest(path: "datasets/stats"), as: DatasetStats.self)
    }

    func images(limit: Int = 50, offset: Int = 0) async throws -> DatasetImagePage {
        let request = APIRequest(
            path: "datasets/images",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
        return try await client.send(request, as: DatasetImagePage.self)
    }

    func image(id: String) async throws -> DatasetImageRecord {
        try await client.send(APIRequest(path: "datasets/images/\(id)"), as: DatasetImageRecord.self)
    }

    func imageData(id: String) async throws -> Data {
        try await client.sendData(APIRequest(path: "datasets/images/\(id)/file"))
    }

    func upload(imageData: Data, metadata: DatasetImageUploadMetadata) async throws -> DatasetImageRecord {
        var form = MultipartFormData()
        form.appendFile(name: "image", filename: "capture.jpg", mimeType: "image/jpeg", contents: imageData)
        form.appendField(name: "source", value: metadata.source.rawValue)
        form.appendField(name: "capture_session_id", value: metadata.captureSessionID)
        form.appendField(name: "review_status", value: metadata.reviewStatus.rawValue)
        if let modelVersion = metadata.modelVersionUsedForPreAnnotation {
            form.appendField(name: "model_version_used_for_pre_annotation", value: modelVersion)
        }
        let annotationsData = try JSONCoding.encode(metadata.annotations)
        guard let annotationsJSON = String(data: annotationsData, encoding: .utf8) else {
            throw APIError.encoding("Annotations are not valid UTF-8")
        }
        form.appendField(name: "annotations", value: annotationsJSON)
        form.finalize()

        let request = APIRequest(
            path: "datasets/images",
            method: .post,
            headers: ["Content-Type": "multipart/form-data; boundary=\(form.boundary)"],
            body: form.data
        )
        return try await client.send(request, as: DatasetImageRecord.self)
    }

    func updateAnnotations(
        imageID: String,
        annotations: [Annotation],
        reviewStatus: ReviewStatus
    ) async throws -> DatasetImageRecord {
        let payload = AnnotationUpdateRequest(annotations: annotations, reviewStatus: reviewStatus)
        let request = APIRequest(
            path: "datasets/images/\(imageID)/annotations",
            method: .put,
            headers: ["Content-Type": "application/json"],
            body: try JSONCoding.encode(payload)
        )
        return try await client.send(request, as: DatasetImageRecord.self)
    }
}
