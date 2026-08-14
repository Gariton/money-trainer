import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Dataset stats contract")
struct DatasetStatsCodingTests {
    @Test("Decodes the server stats fixture with string class keys")
    func decodesServerFixture() throws {
        let data = Data(
            #"{"image_count":482,"object_count":8421,"class_counts":{"jpy_1":1302,"jpy_500":1498},"split_counts":{"train":337,"validation":72,"test":73},"unreviewed_image_count":8,"annotated_image_count":474}"#.utf8
        )
        let stats = try JSONCoding.makeDecoder().decode(DatasetStats.self, from: data)

        #expect(stats.imageCount == 482)
        #expect(stats.boundingBoxCount == 8_421)
        #expect(stats.classCounts[.one] == 1_302)
        #expect(stats.classCounts[.fiveHundred] == 1_498)
        #expect(stats.trainImageCount == 337)
        #expect(stats.validationImageCount == 72)
        #expect(stats.testImageCount == 73)
    }
}
