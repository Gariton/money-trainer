import SwiftUI

struct TrainingStatusIcon: View {
    let status: TrainingJobStatus

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(tint)
            .accessibilityLabel(status.displayName)
    }

    var tint: Color {
        switch status {
        case .completed: .mtSuccess
        case .failed: .mtDanger
        case .queued: .mtIdle
        default: .mtAccent
        }
    }

    private var symbolName: String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .queued: "clock"
        default: "gearshape.2"
        }
    }
}
