import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Annotation API coding")
struct AnnotationCodingTests {
    @Test("API uses upper-left x/y and omits editor-only id")
    func encodesOriginCoordinates() throws {
        let annotation = Annotation(
            denomination: .oneHundred,
            rect: NormalizedRect(centerX: 0.5, centerY: 0.5, width: 0.2, height: 0.4),
            confidence: 0.97
        )

        let data = try JSONCoding.encode(annotation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["class"] as? String == "jpy_100")
        #expect(abs(try #require(object["x"] as? Double) - 0.4) < 0.0001)
        #expect(abs(try #require(object["y"] as? Double) - 0.3) < 0.0001)
        #expect(object["id"] == nil)
    }

    @Test("API origin coordinates decode to the editor center representation")
    func decodesOriginCoordinates() throws {
        let data = Data(#"{"class":"jpy_50","x":0.2,"y":0.3,"width":0.4,"height":0.2}"#.utf8)
        let annotation = try JSONCoding.makeDecoder().decode(Annotation.self, from: data)

        #expect(abs(annotation.rect.centerX - 0.4) < 0.0001)
        #expect(abs(annotation.rect.centerY - 0.4) < 0.0001)
        #expect(annotation.rect.isValid)
    }
}
