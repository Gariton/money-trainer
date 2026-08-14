import PhotosUI
import SwiftUI

struct DatasetView: View {
    @Bindable var viewModel: DatasetViewModel
    let service: any DatasetServiceProtocol

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editorDraft: AnnotationDraft?
    @State private var isShowingCamera = false

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    DatasetStatRow(title: "Images", value: viewModel.stats.imageCount)
                    DatasetStatRow(title: "Objects", value: viewModel.stats.boundingBoxCount)
                    DatasetStatRow(title: "Annotated images", value: viewModel.stats.annotatedImageCount)
                    DatasetStatRow(title: "Unreviewed images", value: viewModel.stats.unreviewedImageCount)
                }

                Section("Instances") {
                    ForEach(CoinDenomination.allCases) { denomination in
                        DatasetStatRow(
                            title: denomination.displayName,
                            value: viewModel.stats.classCounts[denomination, default: 0]
                        )
                    }
                }

                Section("Split by capture session") {
                    DatasetStatRow(title: "Train", value: viewModel.stats.trainImageCount)
                    DatasetStatRow(title: "Validation", value: viewModel.stats.validationImageCount)
                    DatasetStatRow(title: "Test", value: viewModel.stats.testImageCount)
                }

                ActiveCaptureSessionSection(
                    captureSessionID: viewModel.captureSessionID,
                    onStartNew: viewModel.beginNewCaptureSession
                )

                Section("Recent images") {
                    if viewModel.images.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "画像がありません",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("カメラまたは写真ライブラリから追加してください。")
                        )
                    } else {
                        ForEach(viewModel.images) { image in
                            DatasetImageRow(image: image)
                        }
                    }
                }
            }
            .navigationTitle("Dataset")
            .refreshable { await viewModel.load() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("写真を追加", systemImage: "photo.badge.plus")
                    }

                    Button("撮影", systemImage: "camera", action: showCamera)
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.images.isEmpty {
                    ProgressView("Datasetを読み込み中")
                }
            }
            .task { await viewModel.load() }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await importPhoto(newValue) }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView(captureSessionID: viewModel.captureSessionID) { imageData in
                    Task { await openEditor(imageData: imageData, source: .camera) }
                }
            }
            .fullScreenCover(item: $editorDraft) { draft in
                AnnotationEditorView(draft: draft, service: service) {
                    Task { await viewModel.load() }
                }
            }
            .alert("Dataset Error", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel, action: clearError)
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .alert("Annotation", isPresented: $viewModel.isShowingInformation) {
                Button("OK", role: .cancel, action: clearInformation)
            } message: {
                Text(viewModel.informationalMessage ?? "")
            }
        }
    }

    private func showCamera() {
        isShowingCamera = true
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.presentError("選択した画像を読み込めませんでした。")
                return
            }
            let jpegData = try ImageDataNormalizer.jpegData(from: data)
            editorDraft = await viewModel.makeDraft(
                imageData: jpegData,
                source: .photoLibrary,
                captureSessionID: viewModel.captureSessionID
            )
        } catch {
            viewModel.presentError(error.localizedDescription)
        }
    }

    private func openEditor(imageData: Data, source: DatasetSource) async {
        isShowingCamera = false
        do {
            let jpegData = try ImageDataNormalizer.jpegData(from: imageData)
            editorDraft = await viewModel.makeDraft(
                imageData: jpegData,
                source: source,
                captureSessionID: viewModel.captureSessionID
            )
        } catch {
            viewModel.presentError(error.localizedDescription)
        }
    }

    private func clearError() {
        viewModel.clearError()
    }

    private func clearInformation() {
        viewModel.clearInformation()
    }
}
