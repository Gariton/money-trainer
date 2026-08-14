import CoreML
import Testing
@testable import MoneyTrainer

@Suite("YOLO Core ML output decoding")
struct YOLOOutputDecoderTests {
    @Test("Decodes pixel xyxy rows and filters confidence")
    func decodesRows() {
        let decoder = YOLOOutputDecoder(confidenceThreshold: 0.25, modelInputSize: 640)
        let annotations = decoder.decode(rows: [
            [64, 128, 192, 256, 0.90, 4],
            [0.1, 0.1, 0.2, 0.2, 0.10, 0]
        ])

        #expect(annotations.count == 1)
        #expect(annotations.first?.denomination == .oneHundred)
        #expect(abs((annotations.first?.rect.centerX ?? 0) - 0.2) < 0.0001)
        #expect(abs((annotations.first?.rect.centerY ?? 0) - 0.3) < 0.0001)
    }

    @Test("Supports a 1×N×6 MLMultiArray")
    func decodesMultiArray() throws {
        let array = try MLMultiArray(shape: [1, 1, 6], dataType: .double)
        let row = [0.1, 0.2, 0.4, 0.6, 0.8, 1.0]
        for (index, value) in row.enumerated() {
            array[index] = NSNumber(value: value)
        }

        let annotations = YOLOOutputDecoder().decode(array)
        #expect(annotations.count == 1)
        #expect(annotations.first?.denomination == .five)
        #expect(abs((annotations.first?.rect.width ?? 0) - 0.3) < 0.0001)
    }
}
