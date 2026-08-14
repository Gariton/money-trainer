import Foundation

struct ServerErrorPayload: Decodable, Sendable {
    let detail: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case detail
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let text = try? container.decode(String.self, forKey: .detail) {
            detail = text
        } else if let validation = try? container.decode(ServerValidationDetail.self, forKey: .detail) {
            let causes = validation.errors.map(\.message).joined(separator: "\n")
            detail = causes.isEmpty ? validation.code : causes
        } else {
            detail = nil
        }
    }
}
