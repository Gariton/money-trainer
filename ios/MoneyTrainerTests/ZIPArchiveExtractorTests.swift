import Foundation
import Testing
@testable import MoneyTrainer

@Suite("Model ZIP extraction")
struct ZIPArchiveExtractorTests {
    @Test("Extracts the server's deflated mlpackage layout")
    func extractsPackage() throws {
        let fixture = try #require(
            Data(
                base64Encoded: "UEsDBBQAAAAIAAAAIQBDv6ajBAAAAAIAAAAlAAAATW9uZXlEZXRlY3Rvci5tbHBhY2thZ2UvTWFuaWZlc3QuanNvbquuBQBQSwECFAMUAAAACAAAACEAQ7+mowQAAAACAAAAJQAAAAAAAAAAAAAAgAEAAAAATW9uZXlEZXRlY3Rvci5tbHBhY2thZ2UvTWFuaWZlc3QuanNvblBLBQYAAAAAAQABAFMAAABHAAAAAAA="
            )
        )
        let destination = URL.temporaryDirectory
            .appending(path: "MoneyTrainerZIPTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: destination) }

        try ZIPArchiveExtractor().extract(data: fixture, to: destination)

        let manifest = destination
            .appending(path: "MoneyDetector.mlpackage", directoryHint: .isDirectory)
            .appending(path: "Manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifest.path))
        #expect(try Data(contentsOf: manifest) == Data("{}".utf8))
    }
}
