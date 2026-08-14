import SwiftUI

struct TrainingStatusIcon: View {
    let status: TrainingJobStatus

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(style)
            .accessibilityLabel(status.displayName)
    }

    private var symbolName: String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .queued: "clock"
        default: "gearshape.2"
        }
    }

    private var style: Color {
        switch status {
        case .completed: .green
        case .failed: .red
        default: .secondary
        }
    }
}
