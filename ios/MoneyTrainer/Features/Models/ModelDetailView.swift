import SwiftUI

/// 指標・金種別・配布操作・失敗例をまとめる詳細画面。
/// 一覧の1行に全部を詰め込まないための受け皿。
struct ModelDetailView: View {
    let model: ModelRecord
    let baselineMetrics: ModelMetrics?
    let localModel: LocalModelRecord?
    let isActive: Bool
    let installPhase: ModelManager.InstallPhase?
    let reportService: any ModelServiceProtocol
    let onInstall: () -> Void
    let onActivate: (LocalModelRecord) -> Void

    @State private var isConfirmingActivate = false

    var body: some View {
        List {
            Section {
                LabeledContent("データセット", value: model.datasetVersion)
                LabeledContent("作成") {
                    Text(model.createdAt, format: .dateTime.year().month().day().hour().minute())
                }
                LabeledContent("Core ML", value: model.coreMLAvailable ? "あり" : "なし")
            }

            if let metrics = model.metrics {
                Section {
                    ModelMetricsView(
                        metrics: metrics,
                        baselineMetrics: isActive ? nil : baselineMetrics
                    )
                    .padding(.vertical, DesignTokens.Spacing.compact)
                } header: {
                    Text("全体の指標")
                } footer: {
                    if !isActive, baselineMetrics != nil {
                        Text("縦線と差分は、使用中のモデルとの比較です。")
                    }
                }

                if !metrics.perClass.isEmpty {
                    Section("金種別") {
                        PerClassMetricsView(metrics: metrics.perClass)
                            .padding(.vertical, DesignTokens.Spacing.compact)
                    }
                }
            }

            Section("配布") {
                if let installPhase {
                    HStack(spacing: DesignTokens.Spacing.regular) {
                        ProgressView()
                        Text(installPhase.displayName)
                    }
                } else if isActive {
                    Label("このモデルを使用中です", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.mtSuccess)
                } else if let localModel {
                    Button("このモデルを使う", systemImage: "checkmark.seal") {
                        isConfirmingActivate = true
                    }
                } else {
                    Button("ダウンロードして使う", systemImage: "arrow.down.circle", action: onInstall)
                        .disabled(!model.coreMLAvailable)
                    if !model.coreMLAvailable {
                        Text("Core MLパッケージが出力されていないため、端末では使えません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    FailureReportsView(model: model, service: reportService)
                } label: {
                    Label("失敗例を見る", systemImage: "exclamationmark.magnifyingglass")
                }
            } footer: {
                Text("誤検出・未検出のサンプルを確認して、次に集めるデータを決められます。")
            }
        }
        .navigationTitle(model.modelVersion)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "このモデルに切り替えますか？",
            isPresented: $isConfirmingActivate,
            titleVisibility: .visible
        ) {
            if let localModel {
                Button("切り替える") { onActivate(localModel) }
            }
        } message: {
            Text("実機テストの検出結果が、このモデルのものに変わります。")
        }
    }
}
