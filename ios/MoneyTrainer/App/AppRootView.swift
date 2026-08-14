import SwiftUI

struct AppRootView: View {
    let dependencies: AppDependencies

    @State private var selection = AppTab.dataset
    @State private var datasetViewModel: DatasetViewModel
    @State private var trainingViewModel: TrainingViewModel
    @State private var modelsViewModel: ModelsViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _datasetViewModel = State(
            initialValue: DatasetViewModel(
                datasetService: dependencies.datasetService,
                inferenceService: dependencies.inferenceService
            )
        )
        _trainingViewModel = State(
            initialValue: TrainingViewModel(service: dependencies.trainingService)
        )
        _modelsViewModel = State(
            initialValue: ModelsViewModel(manager: dependencies.modelManager)
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dataset", systemImage: "photo.stack", value: .dataset) {
                DatasetView(viewModel: datasetViewModel, service: dependencies.datasetService)
            }

            Tab("Training", systemImage: "bolt.horizontal.circle", value: .training) {
                TrainingView(viewModel: trainingViewModel)
            }

            Tab("Models", systemImage: "shippingbox", value: .models) {
                ModelsView(viewModel: modelsViewModel)
            }

            Tab("Live Test", systemImage: "viewfinder", value: .liveTest) {
                LiveTestView(
                    modelManager: dependencies.modelManager,
                    datasetService: dependencies.datasetService
                )
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(dependencies: dependencies)
            }
        }
    }
}
