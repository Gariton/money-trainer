import SwiftUI

/// 画面上部に出す、回復手段つきのエラー帯。
/// モーダルアラートと違い、内容を隠さず、再試行をその場に置ける。
struct ErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    let onDismiss: () -> Void

    private var tint: Color {
        switch error.kind {
        case .connection, .authentication: .mtWarning
        case .validation, .server, .unknown: .mtDanger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.compact) {
                Image(systemName: error.symbolName)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                    Text(error.title)
                        .font(.subheadline.weight(.semibold))
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(error.recoveryHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Button("閉じる", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if onRetry != nil || (error.suggestsConfiguration && onOpenSettings != nil) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    if let onRetry, error.isRetryable {
                        Button("再試行", systemImage: "arrow.clockwise", action: onRetry)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if error.suggestsConfiguration, let onOpenSettings {
                        Button("設定を開く", systemImage: "gearshape", action: onOpenSettings)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint)
                .frame(width: 3)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
