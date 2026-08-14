import Foundation

actor ModelStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let registryURL: URL
    private let archiveExtractor: ZIPArchiveExtractor

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        archiveExtractor: ZIPArchiveExtractor = ZIPArchiveExtractor()
    ) {
        self.fileManager = fileManager
        self.archiveExtractor = archiveExtractor
        let resolvedRoot = rootURL
            ?? URL.applicationSupportDirectory
                .appending(path: "MoneyTrainer", directoryHint: .isDirectory)
                .appending(path: "Models", directoryHint: .isDirectory)
        self.rootURL = resolvedRoot
        registryURL = resolvedRoot.appending(path: "registry.json")
    }

    func loadRegistry() throws -> ModelRegistrySnapshot {
        try ensureDirectory(rootURL)
        guard fileManager.fileExists(atPath: registryURL.path) else { return .empty }
        let data = try Data(contentsOf: registryURL)
        return try JSONCoding.makeDecoder().decode(ModelRegistrySnapshot.self, from: data)
    }

    func extractDownloadedPackage(_ data: Data, model: ModelRecord) throws -> URL {
        let modelDirectory = rootURL.appending(path: model.id, directoryHint: .isDirectory)
        try ensureDirectory(modelDirectory)
        let archiveURL = modelDirectory.appending(path: "MoneyDetector.mlpackage.zip")
        try data.write(to: archiveURL, options: .atomic)
        let extractionURL = modelDirectory.appending(path: "Package", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: extractionURL.path) {
            try fileManager.removeItem(at: extractionURL)
        }
        try archiveExtractor.extract(data: data, to: extractionURL, fileManager: fileManager)
        guard let packageURL = findModelPackage(in: extractionURL) else {
            throw ZIPArchiveError.packageMissing
        }
        return packageURL
    }

    func installCompiledModel(at temporaryURL: URL, model: ModelRecord) throws -> LocalModelRecord {
        let modelDirectory = rootURL.appending(path: model.id, directoryHint: .isDirectory)
        try ensureDirectory(modelDirectory)
        let destination = modelDirectory.appending(path: "MoneyDetector.mlmodelc", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: temporaryURL, to: destination)
        return LocalModelRecord(
            id: model.id,
            modelVersion: model.modelVersion,
            installedAt: .now,
            compiledPath: destination.path
        )
    }

    func saveRegistry(_ snapshot: ModelRegistrySnapshot) throws {
        try ensureDirectory(rootURL)
        let data = try JSONCoding.makeEncoder().encode(snapshot)
        try data.write(to: registryURL, options: .atomic)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func findModelPackage(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == "MoneyDetector.mlpackage" {
            return url
        }
        return nil
    }
}
