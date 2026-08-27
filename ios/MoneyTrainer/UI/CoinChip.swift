import SwiftUI

/// 金種を実物の大きさ・色・穴の有無で示すチップ。
/// 6項目のsegmented pickerより誤選択が少なく、Dynamic Typeでも壊れにくい。
struct CoinChip: View {
    let denomination: CoinDenomination
    let isSelected: Bool

    @ScaledMetric(relativeTo: .footnote) private var scale: CGFloat = 1

    private var diameter: CGFloat {
        denomination.chipDiameter() * scale
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.tight) {
            ZStack {
                Circle()
                    .fill(denomination.tint)
                    .frame(width: diameter, height: diameter)

                if denomination.hasCenterHole {
                    Circle()
                        .fill(.background)
                        .frame(width: diameter * 0.28, height: diameter * 0.28)
                }

                Circle()
                    .strokeBorder(
                        isSelected ? Color.mtAccent : Color.primary.opacity(0.18),
                        lineWidth: isSelected ? 3 : 1
                    )
                    .frame(width: diameter, height: diameter)
            }
            .frame(
                width: DesignTokens.minimumTapSize,
                height: DesignTokens.minimumTapSize
            )

            Text(denomination.displayName)
                .font(.caption2.weight(isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.7))
                .monospacedDigit()
        }
        .contentShape(.rect)
        .accessibilityLabel(denomination.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 金種チップを横に並べた選択列。
struct CoinDenominationPicker: View {
    @Binding var selection: CoinDenomination
    var onSelect: ((CoinDenomination) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                ForEach(CoinDenomination.allCases) { denomination in
                    Button {
                        selection = denomination
                        onSelect?(denomination)
                        Haptics.selection()
                    } label: {
                        CoinChip(
                            denomination: denomination,
                            isSelected: denomination == selection
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.tight)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("金種")
    }
}
