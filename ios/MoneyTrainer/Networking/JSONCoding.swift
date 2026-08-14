import Foundation

enum JSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = try? fractionalStyle.parse(value) {
                return date
            }
            return try Date.ISO8601FormatStyle().parse(value)
        }
        return decoder
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try makeEncoder().encode(value)
        } catch {
            throw APIError.encoding(error.localizedDescription)
        }
    }
}
