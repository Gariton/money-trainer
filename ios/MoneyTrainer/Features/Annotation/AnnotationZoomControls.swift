import SwiftUI

struct AnnotationZoomControls: View {
    let scale: CGFloat
    let onZoomOut: () -> Void
    let onReset: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onZoomOut) {
                Image(systemName: "minus.magnifyingglass")
                    .frame(
                        width: DesignTokens.minimumTapSize,
                        height: DesignTokens.minimumTapSize
                    )
            }
            .disabled(scale <= DesignTokens.minimumAnnotationZoom)
            .accessibilityLabel("縮小")

            Divider()
                .frame(height: 24)

            Button(action: onReset) {
                Text(scale, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .frame(minWidth: 58, minHeight: DesignTokens.minimumTapSize)
                    .overlay(alignment: .trailing) {
                        Text("×")
                            .foregroundStyle(.secondary)
                            .offset(x: 10)
                    }
            }
            .accessibilityLabel("表示倍率")
            .accessibilityValue(
                Double(scale).formatted(.number.precision(.fractionLength(1))) + "倍"
            )
            .accessibilityHint("ダブルタップで等倍に戻します")

            Divider()
                .frame(height: 24)

            Button(action: onZoomIn) {
                Image(systemName: "plus.magnifyingglass")
                    .frame(
                        width: DesignTokens.minimumTapSize,
                        height: DesignTokens.minimumTapSize
                    )
            }
            .disabled(scale >= DesignTokens.maximumAnnotationZoom)
            .accessibilityLabel("拡大")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: .capsule)
    }
}
