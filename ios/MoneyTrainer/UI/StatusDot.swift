import SwiftUI

/// 状態を色付きの点で示す。色だけに頼らないよう記号を併用できる。
struct StatusDot: View {
    let tint: Color
    var isPulsing = false

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: DesignTokens.statusDotSize, height: DesignTokens.statusDotSize)
            .opacity(isPulsing && isAnimating ? 0.3 : 1)
            .animation(
                isPulsing
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : nil,
                value: isAnimating
            )
            .onAppear { isAnimating = isPulsing }
            .accessibilityHidden(true)
    }
}
