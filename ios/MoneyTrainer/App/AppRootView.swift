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
            initialValue: TrainingViewModel(
                service: dependencies.trainingService,
                developerSettings: dependencies.developerSettings
            )
        )
        _modelsViewModel = State(
            initialValue: ModelsViewModel(manager: dependencies.modelManager)
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.dataset.title, systemImage: AppTab.dataset.symbolName, value: .dataset) {
                DatasetView(viewModel: datasetViewModel, service: dependencies.datasetService)
            }

            Tab(AppTab.training.title, systemImage: AppTab.training.symbolName, value: .training) {
                TrainingView(
                    viewModel: trainingViewModel,
                    onOpenDataset: { selection = .dataset }
                )
            }

            Tab(AppTab.models.title, systemImage: AppTab.models.symbolName, value: .models) {
                ModelsView(viewModel: modelsViewModel)
            }

            Tab(AppTab.liveTest.title, systemImage: AppTab.liveTest.symbolName, value: .liveTest) {
                LiveTestView(
                    modelManager: dependencies.modelManager,
                    datasetService: dependencies.datasetService,
                    onOpenModels: { selection = .models }
                )
            }

            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbolName, value: .settings) {
                SettingsView(dependencies: dependencies)
            }
        }
        .environment(dependencies.imageStore)
        .environment(dependencies.connectionMonitor)
        .environment(\.openSettings, OpenSettingsAction { selection = .settings })
        .task { await dependencies.connectionMonitor.checkAndWait() }
    }
}
