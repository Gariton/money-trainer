import SwiftUI

struct TrainingView: View {
    @Bindable var viewModel: TrainingViewModel
    let onOpenDataset: () -> Void

    @Environment(ConnectionMonitor.self) private var connection
    @Environment(\.openSettings) private var openSettings
    @State private var isConfirmingStart = false

    var body: some View {
        NavigationStack {
            List {
                if let job = viewModel.activeJob {
                    Section {
                        ActiveJobBanner(job: job, onOpenDataset: onOpenDataset)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if viewModel.finishedJobs.isEmpty && !viewModel.isLoading {
                        EmptyStateView(
                            title: "学習履歴がありません",
                            systemImage: "bolt.horizontal.circle",
                            message: "データセットが揃ったら、下のボタンで学習を開始してください。"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.finishedJobs) { job in
                            NavigationLink {
                                TrainingJobDetailView(job: job, onOpenDataset: onOpenDataset)
                            } label: {
                                TrainingJobRow(job: job)
                            }
                        }
                    }
                } header: {
                    Text("履歴")
                }
            }
            .navigationTitle("学習")
            .refreshable { await viewModel.refresh() }
            .safeAreaInset(edge: .bottom) { startBar }
            .safeAreaInset(edge: .top, spacing: 0) { banners }
            .overlay {
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    ProgressView("Jobを読み込み中")
                }
            }
            .task(id: viewModel.activeJobIDs) { await viewModel.monitor() }
            .onChange(of: viewModel.error) { _, newValue in
                guard let newValue else { return }
                connection.noteFailure(newValue)
            }
            .confirmationDialog(
                "新しいモデルを学習しますか？",
                isPresented: $isConfirmingStart,
                titleVisibility: .visible
            ) {
                Button("学習を開始") { Task { await viewModel.startTraining() } }
            } message: {
                Text(
                    viewModel.isMockTrainingEnabled
                        ? "Mock trainingが有効です。実際の学習は行われません。"
                        : "サーバーがDataset validationを実行し、問題がある場合はJobを開始しません。"
                )
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 0) {
            // 同じ原因を二重に出さない。画面固有のエラーがあるときはそちらだけ見せる。
            if viewModel.error == nil {
                ConnectionBanner(monitor: connection) { openSettings() }
            }

            if let error = viewModel.error {
                ErrorBanner(
                    error: error,
                    onRetry: { Task { await viewModel.refresh() } },
                    onOpenSettings: { openSettings() },
                    onDismiss: viewModel.clearError
                )
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: DesignTokens.Spacing.compact) {
            if viewModel.isMockTrainingEnabled {
                Label("Mock trainingが有効です", systemImage: "hammer.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.mtWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("新しいモデルを学習", systemImage: "play.fill") {
                isConfirmingStart = true
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isStarting || viewModel.activeJob != nil)

            if viewModel.activeJob != nil {
                Text("進行中のJobが終わるまで待ってください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.regular)
        .background(.bar)
    }
}
