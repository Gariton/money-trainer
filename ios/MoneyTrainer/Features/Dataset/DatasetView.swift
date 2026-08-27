import PhotosUI
import SwiftUI

struct DatasetView: View {
    @Bindable var viewModel: DatasetViewModel
    let service: any DatasetServiceProtocol

    @Environment(ConnectionMonitor.self) private var connection
    @Environment(\.openSettings) private var openSettings

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var editorDraft: AnnotationDraft?
    @State private var isShowingCamera = false

    private let columns = [
        GridItem(
            .adaptive(minimum: DesignTokens.thumbnailMinimumWidth),
            spacing: DesignTokens.thumbnailGridSpacing
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    notices

                    DatasetSummaryHeader(
                        stats: viewModel.stats,
                        captureSessionID: viewModel.captureSessionID,
                        onStartNewSession: startNewSession
                    )

                    Section {
                        gallery
                    } header: {
                        filterBar
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("データセット")
            .refreshable { await viewModel.load() }
            .safeAreaInset(edge: .bottom) {
                DatasetCaptureBar(
                    selectedPhoto: $selectedPhoto,
                    onCapture: showCamera
                )
            }
            .overlay {
                if viewModel.isPresentingBlockingWork {
                    ProgressView(viewModel.blockingWorkMessage)
                        .padding(DesignTokens.Spacing.loose)
                        .background(.regularMaterial)
                        .clipShape(.rect(cornerRadius: DesignTokens.regularCornerRadius))
                }
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.error) { _, newValue in
                guard let newValue else { return }
                connection.noteFailure(newValue)
            }
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
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var notices: some View {
        // 同じ原因を二重に出さない。画面固有のエラーがあるときはそちらだけ見せる。
        if viewModel.error == nil {
            ConnectionBanner(monitor: connection) { openSettings() }
        }

        if let error = viewModel.error {
            ErrorBanner(
                error: error,
                onRetry: { Task { await viewModel.load() } },
                onOpenSettings: { openSettings() },
                onDismiss: viewModel.clearError
            )
        }

        if let message = viewModel.informationalMessage {
            InlineNotice(message: message, onDismiss: viewModel.clearInformation)
        }
    }

    private var filterBar: some View {
        Picker("表示", selection: $viewModel.filter) {
            ForEach(DatasetFilter.allCases) { option in
                Text("\(option.title) \(viewModel.count(for: option))").tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignTokens.Spacing.comfortable)
        .padding(.vertical, DesignTokens.Spacing.compact)
        .background(.bar)
    }

    @ViewBuilder
    private var gallery: some View {
        if viewModel.isLoading && viewModel.images.isEmpty {
            LazyVGrid(columns: columns, spacing: DesignTokens.thumbnailGridSpacing) {
                ForEach(0..<9, id: \.self) { _ in SkeletonTile() }
            }
        } else if viewModel.filteredImages.isEmpty {
            emptyState
                .padding(.vertical, DesignTokens.Spacing.loose)
        } else {
            LazyVGrid(columns: columns, spacing: DesignTokens.thumbnailGridSpacing) {
                ForEach(viewModel.filteredImages) { image in
                    Button {
                        openExistingImage(image)
                    } label: {
                        DatasetImageTile(image: image)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.images.isEmpty {
            EmptyStateView(
                title: "画像がありません",
                systemImage: "photo.on.rectangle.angled",
                message: "硬貨を撮影するか、写真ライブラリから追加してください。"
            ) {
                Button("撮影する", systemImage: "camera.fill", action: showCamera)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            EmptyStateView(
                title: "\(viewModel.filter.title)の画像はありません",
                systemImage: "line.3.horizontal.decrease.circle",
                message: "別の絞り込みを選ぶと、ほかの画像を確認できます。"
            ) {
                Button("すべて表示") { viewModel.filter = .all }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    private func showCamera() {
        isShowingCamera = true
    }

    private func startNewSession() {
        viewModel.beginNewCaptureSession()
        Haptics.impact()
    }

    private func openExistingImage(_ record: DatasetImageRecord) {
        Task {
            guard let draft = await viewModel.makeEditorDraft(for: record) else { return }
            editorDraft = draft
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.present(message: "選択した画像を読み込めませんでした。")
                return
            }
            let jpegData = try ImageDataNormalizer.jpegData(from: data)
            editorDraft = await viewModel.makeDraft(
                imageData: jpegData,
                source: .photoLibrary,
                captureSessionID: viewModel.captureSessionID
            )
        } catch {
            viewModel.present(error)
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
            viewModel.present(error)
        }
    }
}
