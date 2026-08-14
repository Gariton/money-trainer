import Foundation
import Observation

@MainActor
@Observable
final class ModelsViewModel {
    var manager: ModelManager

    init(manager: ModelManager) {
        self.manager = manager
    }

    var models: [ModelRecord] { manager.remoteModels }
    var isLoading: Bool { manager.isLoading }

    func load() async {
        await manager.load()
    }

    func refresh() async {
        await manager.refreshRemote()
    }

    func install(_ model: ModelRecord) async {
        await manager.downloadCompileAndActivate(model)
    }

    func activate(_ local: LocalModelRecord) async {
        do {
            try await manager.activate(local)
        } catch {
            manager.errorMessage = error.localizedDescription
            manager.isShowingError = true
        }
    }

    var reportService: any ModelServiceProtocol { manager.serviceForReports }
}
