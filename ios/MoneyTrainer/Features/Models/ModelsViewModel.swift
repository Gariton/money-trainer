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
    var activeModel: ModelRecord? { manager.activeModel }

    /// 有効化中のモデルを基準に差分を出す。並び順に依存させない。
    var baselineMetrics: ModelMetrics? {
        manager.activeModel?.metrics
    }

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
            Haptics.success()
        } catch {
            manager.showError(error)
        }
    }

    var reportService: any ModelServiceProtocol { manager.serviceForReports }
}
