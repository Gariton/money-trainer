import SwiftUI

struct SettingsView: View {
    let dependencies: AppDependencies
    @Bindable var configurationStore: APIConfigurationStore

    @State private var isTesting = false
    @State private var connectionMessage: String?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        configurationStore = dependencies.configurationStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: $configurationStore.baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $configurationStore.token)
                        .textContentType(.password)

                    Button("Save Configuration", systemImage: "square.and.arrow.down", action: save)
                    Button("Test Connection", systemImage: "network", action: testConnection)
                        .disabled(isTesting)

                    if isTesting {
                        ProgressView("接続を確認中")
                    } else if let connectionMessage {
                        Label(connectionMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("Security") {
                    LabeledContent("Token storage", value: "Keychain")
                    Text("TokenはUserDefaultsやソースコードへ保存しません。")
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Target", value: "iOS 26+")
                    LabeledContent("Classes", value: "6 Japanese coins")
                }
            }
            .navigationTitle("Settings")
            .alert("Configuration Error", isPresented: $configurationStore.isShowingError) {
                Button("OK", role: .cancel, action: configurationStore.clearError)
            } message: {
                Text(configurationStore.errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() {
        guard configurationStore.persist() else { return }
        Task { await dependencies.applyConfiguration() }
    }

    private func testConnection() {
        guard configurationStore.persist() else { return }
        Task {
            isTesting = true
            defer { isTesting = false }
            await dependencies.applyConfiguration()
            do {
                let stats = try await dependencies.datasetService.stats()
                connectionMessage = "接続済み（画像 \(stats.imageCount)件）"
            } catch {
                connectionMessage = nil
                configurationStore.errorMessage = error.localizedDescription
                configurationStore.isShowingError = true
            }
        }
    }
}
