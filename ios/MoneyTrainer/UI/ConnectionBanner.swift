import SwiftUI

/// 未接続のときだけ画面上部に出る細い警告帯。
struct ConnectionBanner: View {
    let monitor: ConnectionMonitor
    let onOpenSettings: () -> Void

    var body: some View {
        if let failure = monitor.failure {
            HStack(spacing: DesignTokens.Spacing.compact) {
                Image(systemName: failure.symbolName)
                Text(failure.title)
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
                Button("設定", action: onOpenSettings)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
            }
            .foregroundStyle(Color.mtWarning)
            .padding(.horizontal, DesignTokens.Spacing.comfortable)
            .padding(.vertical, DesignTokens.Spacing.compact)
            .frame(maxWidth: .infinity)
            .background(Color.mtWarning.opacity(0.12))
            .accessibilityElement(children: .combine)
        }
    }
}
