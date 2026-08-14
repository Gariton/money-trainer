import Foundation

struct ModelMetrics: Codable, Equatable, Sendable {
    let map50: Double
    let map50To95: Double
    let precision: Double
    let recall: Double
    let perClass: [CoinDenomination: ClassMetrics]

    init(
        map50: Double,
        map50To95: Double,
        precision: Double,
        recall: Double,
        perClass: [CoinDenomination: ClassMetrics]
    ) {
        self.map50 = map50
        self.map50To95 = map50To95
        self.precision = precision
        self.recall = recall
        self.perClass = perClass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        map50 = try Self.decodeDouble(from: container, keys: ["map50", "mAP50"])
        map50To95 = try Self.decodeDouble(from: container, keys: ["map50_95", "mAP50-95"])
        precision = try Self.decodeDouble(from: container, keys: ["precision"])
        recall = try Self.decodeDouble(from: container, keys: ["recall"])
        let perClassKey = ["per_class", "perClass"]
            .map(FlexibleCodingKey.init)
            .first(where: container.contains)
        let rawMetrics = try perClassKey.map {
            try container.decode([String: ClassMetrics].self, forKey: $0)
        } ?? [:]
        perClass = Dictionary(
            uniqueKeysWithValues: rawMetrics.compactMap { rawName, metrics in
                CoinDenomination(rawValue: rawName).map { denomination in
                    (denomination, metrics)
                }
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKey.self)
        try container.encode(map50, forKey: FlexibleCodingKey("map50"))
        try container.encode(map50To95, forKey: FlexibleCodingKey("map50_95"))
        try container.encode(precision, forKey: FlexibleCodingKey("precision"))
        try container.encode(recall, forKey: FlexibleCodingKey("recall"))
        let rawMetrics = Dictionary(
            uniqueKeysWithValues: perClass.map { denomination, metrics in
                (denomination.rawValue, metrics)
            }
        )
        try container.encode(rawMetrics, forKey: FlexibleCodingKey("per_class"))
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<FlexibleCodingKey>,
        keys: [String]
    ) throws -> Double {
        for key in keys.map(FlexibleCodingKey.init) where container.contains(key) {
            return try container.decode(Double.self, forKey: key)
        }
        throw DecodingError.keyNotFound(
            FlexibleCodingKey(keys[0]),
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing metric")
        )
    }
}
