import SwiftUI

struct SettingsView: View {
    let dependencies: AppDependencies
    @Bindable var configurationStore: APIConfigurationStore
    @Bindable var developerSettings: DeveloperSettings

    @Environment(ConnectionMonitor.self) private var connection

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        configurationStore = dependencies.configurationStore
        developerSettings = dependencies.developerSettings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    connectionRow
                } header: {
                    Text("接続状態")
                } footer: {
                    Text("入力を変えると自動で保存し、接続を確認します。")
                }

                Section("サーバー") {
                    TextField("Base URL", text: $configurationStore.baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .monospaced()

                    SecureField("Bearer token", text: $configurationStore.token)
                        .textContentType(.password)
                }

                Section {
                    LabeledContent("Tokenの保存先", value: "Keychain")
                } header: {
                    Text("セキュリティ")
                } footer: {
                    Text("TokenはUserDefaultsやソースコードへ保存しません。")
                }

                Section {
                    Toggle("Mock training", isOn: $developerSettings.isMockTrainingEnabled)
                } header: {
                    Text("開発")
                } footer: {
                    Text("有効にすると、実際の学習を行わずにJobの流れだけを確認できます。")
                }

                Section("このアプリについて") {
                    LabeledContent("対象クラス", value: "日本円硬貨 6金種")
                    LabeledContent("必要なiOS", value: "26以降")
                }
            }
            .navigationTitle("設定")
            .safeAreaInset(edge: .top, spacing: 0) {
                if let error = configurationStore.error {
                    ErrorBanner(error: error, onDismiss: configurationStore.clearError)
                }
            }
            // 入力が落ち着いてから保存・接続確認する。保存ボタンは持たない。
            .task(id: configurationKey) {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                applyConfiguration()
            }
        }
    }

    private var configurationKey: String {
        "\(configurationStore.baseURLText)|\(configurationStore.token)"
    }

    @ViewBuilder
    private var connectionRow: some View {
        switch connection.state {
        case .unknown:
            Label("未確認", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: DesignTokens.Spacing.regular) {
                ProgressView()
                Text("接続を確認中")
            }
        case let .connected(imageCount):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                Label("接続済み", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.mtSuccess)
                Text("Dataset画像 \(imageCount)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case let .failed(error):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                Label(error.title, systemImage: error.symbolName)
                    .foregroundStyle(Color.mtWarning)
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("もう一度確認", systemImage: "arrow.clockwise") {
                    connection.check()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func applyConfiguration() {
        guard configurationStore.persist() else { return }
        Task { await dependencies.applyConfiguration() }
    }
}
