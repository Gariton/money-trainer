import SwiftUI

/// 数値を細い横棒で示す。表とパーセント羅列の代替。
struct MeterBar: View {
    let value: Double
    var total: Double = 1
    var tint: Color = .mtAccent
    var target: Double?

    private var fraction: Double {
        guard total > 0, value.isFinite else { return 0 }
        return min(max(value / total, 0), 1)
    }

    private var targetFraction: Double? {
        guard let target, total > 0 else { return nil }
        return min(max(target / total, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)

                if let targetFraction {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 1.5)
                        .offset(x: proxy.size.width * targetFraction)
                        .opacity(0.5)
                }
            }
        }
        .frame(height: DesignTokens.meterHeight)
        .accessibilityHidden(true)
    }
}
