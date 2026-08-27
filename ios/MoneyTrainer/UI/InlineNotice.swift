import SwiftUI

/// 自動処理の結果など、失敗ではない知らせを流れの中で伝える帯。
/// モーダルアラートで作業を止めないために使う。
struct InlineNotice: View {
    let message: String
    var systemImage = "sparkles"
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.compact) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.mtAccent)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("閉じる", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.regular)
        .frame(maxWidth: .infinity)
        .background(Color.mtAccent.opacity(0.10))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

/// 読み込み中に既存の内容を隠さないためのプレースホルダタイル。
struct SkeletonTile: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fill)
            .accessibilityHidden(true)
    }
}
