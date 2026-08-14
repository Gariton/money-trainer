import SwiftUI
import Testing
@testable import MoneyTrainer

@MainActor
@Suite("Image upload normalization")
struct ImageDataNormalizerTests {
    @Test("Converts supported source images to JPEG magic bytes")
    func convertsToJPEG() throws {
        let source = try #require(UIImage(systemName: "circle.fill")?.pngData())
        let result = try ImageDataNormalizer.jpegData(from: source)

        #expect(result.starts(with: [0xFF, 0xD8, 0xFF]))
    }
}
