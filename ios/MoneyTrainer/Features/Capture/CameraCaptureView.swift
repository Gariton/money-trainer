import SwiftUI

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CameraCaptureViewModel()

    let captureSessionID: String
    let onCapture: (Data) -> Void

    var body: some View {
        NavigationStack {
            CameraPreview(session: viewModel.session)
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    Label("Session \(captureSessionID.prefix(8))", systemImage: "link")
                        .font(.footnote)
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(.rect(cornerRadius: DesignTokens.compactCornerRadius))
                        .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    Button("写真を撮影", systemImage: "camera.circle.fill", action: capture)
                        .font(.title2)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!viewModel.isReady || viewModel.isCapturing)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("閉じる", systemImage: "xmark", action: dismiss.callAsFunction)
                    }
                }
                .overlay {
                    if !viewModel.isReady {
                        ProgressView("カメラを準備中")
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(.rect(cornerRadius: DesignTokens.compactCornerRadius))
                    }
                }
                .task { await viewModel.start() }
                .onDisappear(perform: viewModel.stop)
                .alert("Camera Error", isPresented: $viewModel.isShowingError) {
                    Button("OK", role: .cancel, action: viewModel.clearError)
                } message: {
                    Text(viewModel.errorMessage)
                }
        }
    }

    private func capture() {
        Task {
            guard let data = await viewModel.capture() else { return }
            onCapture(data)
            dismiss()
        }
    }
}
