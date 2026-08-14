import SwiftUI

struct FailureReportDetailView: View {
    let item: FailureReportItem
    let loadData: () async throws -> Data

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Reportを読み込み中")
            } else if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(item.categoryDisplayName)
                }
            } else {
                ContentUnavailableView(
                    "Reportを表示できません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage ?? "画像形式ではありません。")
                )
            }
        }
        .navigationTitle(item.categoryDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let data = try await loadData()
            guard let decoded = UIImage(data: data) else {
                errorMessage = "Content-Type: \(item.contentType)"
                return
            }
            image = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
