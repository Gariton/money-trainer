import SwiftUI

/// いま実機で使われているモデルを画面上部に常時出す。
/// 一覧の中に紛れさせない。
struct ActiveModelHeader: View {
    let model: ModelRecord?
    let localModel: LocalModelRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                StatusDot(tint: model == nil ? .mtIdle : .mtSuccess)
                Text("使用中のモデル")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let model {
                Text(model.modelVersion)
                    .font(.title3.weight(.bold))
                    .monospaced()

                HStack(spacing: DesignTokens.Spacing.compact) {
                    if let metrics = model.metrics {
                        Text("mAP50–95 \(metrics.map50To95.formatted(.percent.precision(.fractionLength(1))))")
                    }
                    if let localModel {
                        Text("・")
                        Text(localModel.installedAt, format: .dateTime.month().day())
                        Text("導入")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                Text("まだ有効化されていません")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("学習済みモデルをダウンロードすると、実機テストで使えます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mtSurface)
        .accessibilityElement(children: .combine)
    }
}
