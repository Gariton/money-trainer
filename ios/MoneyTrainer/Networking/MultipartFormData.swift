import Foundation

struct MultipartFormData: Sendable {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "MoneyTrainer-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func appendField(name: String, value: String) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.appendUTF8("\(value)\r\n")
    }

    mutating func appendJSON<Value: Encodable>(name: String, value: Value) throws {
        let encoded = try JSONCoding.encode(value)
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        data.appendUTF8("Content-Type: application/json\r\n\r\n")
        data.append(encoded)
        data.appendUTF8("\r\n")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, contents: Data) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        data.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        data.append(contents)
        data.appendUTF8("\r\n")
    }

    mutating func finalize() {
        data.appendUTF8("--\(boundary)--\r\n")
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
