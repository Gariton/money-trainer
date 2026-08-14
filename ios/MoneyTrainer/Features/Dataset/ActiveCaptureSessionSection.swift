import SwiftUI

struct ActiveCaptureSessionSection: View {
    let captureSessionID: String
    let onStartNew: () -> Void

    var body: some View {
        Section {
            LabeledContent(
                "Session ID",
                value: String(captureSessionID.prefix(8))
            )
            Button(
                "Start New Session",
                systemImage: "arrow.triangle.2.circlepath",
                action: onStartNew
            )
        } header: {
            Text("Active capture session")
        } footer: {
            Text("同じ撮影条件の画像は同じSessionに追加し、照明・背景・場所を変えたときに新しいSessionを開始してください。")
        }
    }
}
