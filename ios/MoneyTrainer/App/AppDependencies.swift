import Foundation
import Observation

@MainActor
@Observable
final class AppDependencies {
    let configurationStore: APIConfigurationStore
    let apiClient: APIClient
    let datasetService: DatasetService
    let inferenceService: InferenceService
    let trainingService: TrainingService
    let modelService: ModelService
    let modelManager: ModelManager
    let connectionMonitor: ConnectionMonitor
    let imageStore: DatasetImageStore
    let developerSettings: DeveloperSettings

    init(configurationStore: APIConfigurationStore = APIConfigurationStore()) {
        self.configurationStore = configurationStore
        let configuration = configurationStore.configuration
        let client = APIClient(baseURL: configuration.baseURL, token: configuration.token)
        apiClient = client
        let dataset = DatasetService(client: client)
        datasetService = dataset
        inferenceService = InferenceService(client: client)
        trainingService = TrainingService(client: client)
        modelService = ModelService(client: client)
        modelManager = ModelManager(service: ModelService(client: client))
        connectionMonitor = ConnectionMonitor(service: dataset)
        imageStore = DatasetImageStore(service: dataset)
        developerSettings = DeveloperSettings()
    }

    func applyConfiguration() async {
        let configuration = configurationStore.configuration
        await apiClient.updateConfiguration(
            baseURL: configuration.baseURL,
            token: configuration.token
        )
        imageStore.removeAll()
        await connectionMonitor.checkAndWait()
    }
}
