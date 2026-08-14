import Foundation
import Observation

@MainActor
@Observable
final class ModelManager {
    private(set) var remoteModels: [ModelRecord] = []
    private(set) var localModels: [LocalModelRecord] = []
    private(set) var activeModelID: String?
    private(set) var activeModelURL: URL?
    private(set) var installingModelIDs: Set<String> = []
    private(set) var isLoading = false
    var isShowingError = false
    var errorMessage = ""

    @ObservationIgnored private let service: any ModelServiceProtocol
    @ObservationIgnored private let store: ModelStore
    @ObservationIgnored private let compiler: ModelCompiler

    init(
        service: any ModelServiceProtocol,
        store: ModelStore = ModelStore(),
        compiler: ModelCompiler = ModelCompiler()
    ) {
        self.service = service
        self.store = store
        self.compiler = compiler
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let registry = try await store.loadRegistry()
            localModels = registry.models
            activeModelID = registry.activeModelID
            activeModelURL = localModels
                .first(where: { $0.id == activeModelID })
                .map { URL(filePath: $0.compiledPath) }
            remoteModels = try await service.models()
                .sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            showError(error.localizedDescription)
        }
    }

    func refreshRemote() async {
        do {
            remoteModels = try await service.models()
                .sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            showError(error.localizedDescription)
        }
    }

    func downloadCompileAndActivate(_ model: ModelRecord) async {
        guard !installingModelIDs.contains(model.id) else { return }
        installingModelIDs.insert(model.id)
        defer { installingModelIDs.remove(model.id) }
        do {
            let data = try await service.download(id: model.id)
            let sourceURL = try await store.extractDownloadedPackage(data, model: model)
            let compiledURL = try await compiler.compileAndValidate(sourceURL: sourceURL)
            let local = try await store.installCompiledModel(at: compiledURL, model: model)
            localModels.removeAll(where: { $0.id == local.id })
            localModels.append(local)
            try await activate(local)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func activate(_ localModel: LocalModelRecord) async throws {
        let url = URL(filePath: localModel.compiledPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelManagerError.compiledModelMissing
        }
        activeModelID = localModel.id
        activeModelURL = url
        if !localModels.contains(where: { $0.id == localModel.id }) {
            localModels.append(localModel)
        }
        try await saveRegistry()
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    func localModel(id: String) -> LocalModelRecord? {
        localModels.first(where: { $0.id == id })
    }

    var serviceForReports: any ModelServiceProtocol { service }

    private func saveRegistry() async throws {
        try await store.saveRegistry(
            ModelRegistrySnapshot(models: localModels, activeModelID: activeModelID)
        )
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
