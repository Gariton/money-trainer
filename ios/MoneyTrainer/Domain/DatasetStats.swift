import Foundation

struct DatasetStats: Codable, Equatable, Sendable {
    var imageCount: Int
    var boundingBoxCount: Int
    var classCounts: [CoinDenomination: Int]
    var trainImageCount: Int
    var validationImageCount: Int
    var testImageCount: Int
    var unreviewedImageCount: Int
    var annotatedImageCount: Int

    static let empty = DatasetStats(
        imageCount: 0,
        boundingBoxCount: 0,
        classCounts: [:],
        trainImageCount: 0,
        validationImageCount: 0,
        testImageCount: 0,
        unreviewedImageCount: 0,
        annotatedImageCount: 0
    )

    private enum CodingKeys: String, CodingKey {
        case imageCount = "image_count"
        case objectCount = "object_count"
        case classCounts = "class_counts"
        case splitCounts = "split_counts"
        case unreviewedImageCount = "unreviewed_image_count"
        case annotatedImageCount = "annotated_image_count"
    }

    init(
        imageCount: Int,
        boundingBoxCount: Int,
        classCounts: [CoinDenomination: Int],
        trainImageCount: Int,
        validationImageCount: Int,
        testImageCount: Int,
        unreviewedImageCount: Int,
        annotatedImageCount: Int
    ) {
        self.imageCount = imageCount
        self.boundingBoxCount = boundingBoxCount
        self.classCounts = classCounts
        self.trainImageCount = trainImageCount
        self.validationImageCount = validationImageCount
        self.testImageCount = testImageCount
        self.unreviewedImageCount = unreviewedImageCount
        self.annotatedImageCount = annotatedImageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? 0
        boundingBoxCount = try container.decodeIfPresent(Int.self, forKey: .objectCount) ?? 0
        let rawClassCounts = try container.decodeIfPresent([String: Int].self, forKey: .classCounts) ?? [:]
        classCounts = Dictionary(
            uniqueKeysWithValues: rawClassCounts.compactMap { rawName, count in
                CoinDenomination(rawValue: rawName).map { denomination in
                    (denomination, count)
                }
            }
        )
        let splits = try container.decodeIfPresent([String: Int].self, forKey: .splitCounts) ?? [:]
        trainImageCount = splits["train", default: 0]
        validationImageCount = splits["validation", default: 0]
        testImageCount = splits["test", default: 0]
        unreviewedImageCount = try container.decodeIfPresent(Int.self, forKey: .unreviewedImageCount) ?? 0
        annotatedImageCount = try container.decodeIfPresent(Int.self, forKey: .annotatedImageCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageCount, forKey: .imageCount)
        try container.encode(boundingBoxCount, forKey: .objectCount)
        let rawClassCounts = Dictionary(
            uniqueKeysWithValues: classCounts.map { denomination, count in
                (denomination.rawValue, count)
            }
        )
        try container.encode(rawClassCounts, forKey: .classCounts)
        try container.encode(
            ["train": trainImageCount, "validation": validationImageCount, "test": testImageCount],
            forKey: .splitCounts
        )
        try container.encode(unreviewedImageCount, forKey: .unreviewedImageCount)
        try container.encode(annotatedImageCount, forKey: .annotatedImageCount)
    }
}
