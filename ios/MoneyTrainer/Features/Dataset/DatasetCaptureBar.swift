import PhotosUI
import SwiftUI

/// このアプリの主動作である撮影を、親指の届く画面下部の主ボタンとして置く。
struct DatasetCaptureBar: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.regular) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.title3)
                    .frame(
                        width: DesignTokens.minimumTapSize,
                        height: DesignTokens.minimumTapSize
                    )
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("写真ライブラリから追加")

            Button("撮影", systemImage: "camera.fill", action: onCapture)
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.regular)
        .background(.bar)
    }
}
