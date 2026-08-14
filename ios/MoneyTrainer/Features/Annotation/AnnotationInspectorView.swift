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

                if viewModel.selectedAnnotation?.requiresReview(
                    threshold: DesignTokens.lowConfidenceThreshold
                ) == true {
                    Label("低confidenceのため要確認", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("要確認: 低confidence")
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
