import SwiftUI

struct CoinCountSummaryView: View {
    @Bindable var viewModel: LiveTestViewModel
    let correctAction: () -> Void

    var body: some View {
        VStack {
            Grid(alignment: .leading, horizontalSpacing: 16) {
                ForEach(CoinDenomination.allCases) { denomination in
                    GridRow {
                        Text(denomination.displayName)
                        Text("× \(viewModel.count(for: denomination))")
                            .monospacedDigit()
                    }
                }
            }

            HStack {
                Text("Total")
                    .bold()
                Spacer()
                Text(viewModel.total, format: .currency(code: "JPY").precision(.fractionLength(0)))
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
            }

            Button("Correct Detection", systemImage: "pencil.and.list.clipboard", action: correctAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedDetectionID == nil)
        }
        .padding()
        .background(.regularMaterial)
    }
}
