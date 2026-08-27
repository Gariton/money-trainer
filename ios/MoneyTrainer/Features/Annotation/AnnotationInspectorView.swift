import SwiftUI

struct AnnotationInspectorView: View {
    @Bindable var viewModel: AnnotationEditorViewModel

    var body: some View {
        VStack(alignment: .leading) {
            if viewModel.selectedAnnotation == nil {
                Label("Bounding Boxを選択してください", systemImage: "rectangle.dashed")
                    .foregroundStyle(.secondary)
            } else {
                Picker("金種", selection: $viewModel.selectedDenomination) {
                    ForEach(CoinDenomination.allCases) { denomination in
                        Text(denomination.displayName).tag(denomination)
                    }
                }
                .pickerStyle(.segmented)

                if let selectedAnnotation = viewModel.selectedAnnotation,
                   selectedAnnotation.requiresReview(
                    threshold: DesignTokens.lowConfidenceThreshold
                   ) {
                    if selectedAnnotation.confidence == nil {
                        Label("円形候補です。金種を確認してください", systemImage: "circle.dashed")
                            .foregroundStyle(.orange)
                        Button(
                            "この金種で確定",
                            systemImage: "checkmark.circle",
                            action: viewModel.confirmSelected
                        )
                        .buttonStyle(.borderedProminent)
                    } else {
                        Label("低confidenceのため要確認", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("要確認: 低confidence")
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
