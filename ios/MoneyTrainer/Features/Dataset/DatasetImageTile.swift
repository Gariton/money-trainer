import SwiftUI

/// 一覧の主役。角丸・影・枠を付けず、端まで使ったタイルとして並べる。
struct DatasetImageTile: View {
    let image: DatasetImageRecord

    private var needsAttention: Bool { image.needsAttention }

    var body: some View {
        DatasetImageThumbnail(imageID: image.id)
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                if needsAttention {
                    Rectangle()
                        .fill(Color.mtWarning)
                        .frame(height: 3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: DesignTokens.Spacing.tight) {
                    if needsAttention {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.mtWarning)
                    }
                    Image(systemName: "rectangle.dashed")
                    Text(image.annotations.count, format: .number)
                        .monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.compact)
                .padding(.vertical, DesignTokens.Spacing.tight)
                .background(.black.opacity(0.55))
                .padding(DesignTokens.Spacing.tight)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let status = needsAttention ? "要確認" : "確認済み"
        let date = image.createdAt.formatted(.dateTime.month().day().hour().minute())
        return "\(image.source.displayName)、BBox \(image.annotations.count)件、\(status)、\(date)"
    }
}
