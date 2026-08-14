import Foundation

struct ClassMetrics: Codable, Equatable, Sendable {
    let precision: Double
    let recall: Double
    let averagePrecision: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        precision = try container.decode(Double.self, forKey: FlexibleCodingKey("precision"))
        recall = try container.decode(Double.self, forKey: FlexibleCodingKey("recall"))
        if container.contains(FlexibleCodingKey("ap")) {
            averagePrecision = try container.decode(Double.self, forKey: FlexibleCodingKey("ap"))
        } else {
            averagePrecision = try container.decode(Double.self, forKey: FlexibleCodingKey("AP"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKey.self)
        try container.encode(precision, forKey: FlexibleCodingKey("precision"))
        try container.encode(recall, forKey: FlexibleCodingKey("recall"))
        try container.encode(averagePrecision, forKey: FlexibleCodingKey("ap"))
    }
}
