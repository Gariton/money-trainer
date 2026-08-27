import Foundation

struct Annotation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var denomination: CoinDenomination
    var rect: NormalizedRect
    var confidence: Double?
    var needsReview: Bool?

    init(
        id: UUID = UUID(),
        denomination: CoinDenomination,
        rect: NormalizedRect,
        confidence: Double? = nil,
        needsReview: Bool? = nil
    ) {
        self.id = id
        self.denomination = denomination
        self.rect = rect
        self.confidence = confidence
        self.needsReview = needsReview
    }

    func requiresReview(threshold: Double) -> Bool {
        if let needsReview { return needsReview }
        guard let confidence else { return false }
        return confidence < threshold
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case denomination = "class"
        case legacyDenomination = "class_name"
        case x
        case y
        case width
        case height
        case confidence
        case needsReview = "needs_review"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        denomination = try container.decodeIfPresent(CoinDenomination.self, forKey: .denomination)
            ?? container.decode(CoinDenomination.self, forKey: .legacyDenomination)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        rect = NormalizedRect(
            centerX: x + width / 2,
            centerY: y + height / 2,
            width: width,
            height: height
        )
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(denomination, forKey: .denomination)
        try container.encode(rect.minX, forKey: .x)
        try container.encode(rect.minY, forKey: .y)
        try container.encode(rect.width, forKey: .width)
        try container.encode(rect.height, forKey: .height)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(needsReview, forKey: .needsReview)
    }
}
