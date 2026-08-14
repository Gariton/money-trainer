import SwiftUI

struct TrainingView: View {
    @Bindable var viewModel: TrainingViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Mock training", isOn: $viewModel.mockMode)
                    Button("Train New Model", systemImage: "play.fill", action: startTraining)
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isStarting)
                } footer: {
                    Text("サーバーがDataset validationを実行し、問題がある場合はJobを開始しません。")
                }

                Section("Jobs") {
                    if viewModel.jobs.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "Training Jobがありません",
                            systemImage: "bolt.horizontal.circle",
                            description: Text("Datasetを確認して新しいモデルを学習してください。")
                        )
                    } else {
                        ForEach(viewModel.jobs) { job in
                            TrainingJobRow(job: job)
                        }
                    }
                }
            }
            .navigationTitle("Training")
            .refreshable { await viewModel.refresh() }
            .overlay {
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    ProgressView("Jobsを読み込み中")
                }
            }
            .task(id: viewModel.activeJobIDs) { await viewModel.monitor() }
            .alert("Training Error", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel, action: viewModel.clearError)
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private func startTraining() {
        Task { await viewModel.startTraining() }
    }
}
