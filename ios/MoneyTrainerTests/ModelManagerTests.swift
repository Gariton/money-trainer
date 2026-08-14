import Foundation
import Testing
@testable import MoneyTrainer

@MainActor
@Suite("Model management")
struct ModelManagerTests {
    @Test("Activation persists and reloads the active compiled model")
    func activationPersists() async throws {
        let root = URL.temporaryDirectory.appending(path: "MoneyTrainerModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let compiled = root.appending(path: "v1.mlmodelc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        let store = ModelStore(rootURL: root)
        let manager = ModelManager(service: MockModelService(), store: store)
        let local = LocalModelRecord(
            id: "model-1",
            modelVersion: "v1",
            installedAt: .now,
            compiledPath: compiled.path
        )

        try await manager.activate(local)
        let reloaded = ModelManager(service: MockModelService(), store: store)
        await reloaded.load()

        #expect(reloaded.activeModelID == "model-1")
        #expect(reloaded.activeModelURL?.standardizedFileURL.path == compiled.standardizedFileURL.path)
        #expect(reloaded.localModels.map(\.id) == ["model-1"])
    }
}
