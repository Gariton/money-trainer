import Foundation
import Observation

@MainActor
@Observable
final class ModelManager {
    enum InstallPhase: String, Sendable {
        case downloading
        case compiling
        case activating

        var displayName: String {
            switch self {
            case .downloading: "ダウンロード中"
            case .compiling: "コンパイル中"
            case .activating: "有効化中"
            }
        }
    }

    private(set) var remoteModels: [ModelRecord] = []
    private(set) var localModels: [LocalModelRecord] = []
    private(set) var activeModelID: String?
    private(set) var activeModelURL: URL?
    private(set) var installingModelIDs: Set<String> = []
    /// 「Download → Compile → Activate」を一括表示せず、いま何をしているかを出す。
    private(set) var installPhases: [String: InstallPhase] = [:]
    private(set) var isLoading = false
    var error: AppError?

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
            showError(error)
        }
    }

    func refreshRemote() async {
        do {
            remoteModels = try await service.models()
                .sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            showError(error)
        }
    }

    func downloadCompileAndActivate(_ model: ModelRecord) async {
        guard !installingModelIDs.contains(model.id) else { return }
        installingModelIDs.insert(model.id)
        defer {
            installingModelIDs.remove(model.id)
            installPhases[model.id] = nil
        }
        do {
            installPhases[model.id] = .downloading
            let data = try await service.download(id: model.id)
            installPhases[model.id] = .compiling
            let sourceURL = try await store.extractDownloadedPackage(data, model: model)
            let compiledURL = try await compiler.compileAndValidate(sourceURL: sourceURL)
            let local = try await store.installCompiledModel(at: compiledURL, model: model)
            localModels.removeAll(where: { $0.id == local.id })
            localModels.append(local)
            installPhases[model.id] = .activating
            try await activate(local)
            Haptics.success()
        } catch {
            showError(error)
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
        error = nil
    }

    func localModel(id: String) -> LocalModelRecord? {
        localModels.first(where: { $0.id == id })
    }

    var serviceForReports: any ModelServiceProtocol { service }

    var activeModel: ModelRecord? {
        remoteModels.first(where: { $0.id == activeModelID })
    }

    var activeLocalModel: LocalModelRecord? {
        localModels.first(where: { $0.id == activeModelID })
    }

    func installPhase(for modelID: String) -> InstallPhase? {
        installPhases[modelID]
    }

    private func saveRegistry() async throws {
        try await store.saveRegistry(
            ModelRegistrySnapshot(models: localModels, activeModelID: activeModelID)
        )
    }

    func showError(_ error: any Error) {
        self.error = AppError(error, title: "モデルを操作できません")
        Haptics.failure()
    }
}
