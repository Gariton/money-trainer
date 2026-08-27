import Observation
import SwiftUI

@MainActor
@Observable
final class AnnotationEditorViewModel {
    let draft: AnnotationDraft
    let image: UIImage
    let imageSize: CGSize

    private(set) var annotations: [Annotation]
    var selectedAnnotationID: UUID?
    private(set) var isSaving = false
    var error: AppError?

    /// 直前の状態を積む。削除・追加の取り消しに使う。
    @ObservationIgnored private var history: [[Annotation]] = []
    @ObservationIgnored private let historyLimit = 20
    @ObservationIgnored private let service: any DatasetServiceProtocol
    @ObservationIgnored private let originalAnnotations: [Annotation]

    init(draft: AnnotationDraft, service: any DatasetServiceProtocol) {
        self.draft = draft
        self.service = service
        let decodedImage = UIImage(data: draft.imageData) ?? UIImage()
        image = decodedImage
        imageSize = decodedImage.size
        annotations = draft.annotations
        originalAnnotations = draft.annotations
        selectedAnnotationID = draft.annotations
            .first(where: {
                $0.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
            })?
            .id
            ?? draft.annotations.first?.id
    }

    // MARK: - 進捗

    var isEditingExistingImage: Bool { draft.isEditingExistingImage }

    var pendingReviewCount: Int {
        annotations.count {
            $0.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
        }
    }

    var confirmedCount: Int { annotations.count - pendingReviewCount }

    var hasPendingReview: Bool { pendingReviewCount > 0 }

    var progressLabel: String {
        annotations.isEmpty
            ? "Bounding Boxがありません"
            : "確認済み \(confirmedCount) / \(annotations.count)"
    }

    var hasUnsavedChanges: Bool { annotations != originalAnnotations }

    var canUndo: Bool { !history.isEmpty }

    // MARK: - 選択

    var selectedDenomination: CoinDenomination {
        get {
            annotations.first(where: { $0.id == selectedAnnotationID })?.denomination ?? .one
        }
        set {
            guard let index = selectedIndex else { return }
            annotations[index].denomination = newValue
            annotations[index].needsReview = false
        }
    }

    var selectedAnnotation: Annotation? {
        annotations.first(where: { $0.id == selectedAnnotationID })
    }

    var selectedRequiresReview: Bool {
        selectedAnnotation?.requiresReview(
            threshold: DesignTokens.lowConfidenceThreshold
        ) ?? false
    }

    func select(_ id: UUID) {
        selectedAnnotationID = id
    }

    /// 要確認のBounding Boxを順に送る。エディタの主動線。
    func selectNextNeedingReview() {
        let pending = annotations.filter {
            $0.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
        }
        guard !pending.isEmpty else { return }
        guard let current = selectedAnnotationID,
              let currentIndex = pending.firstIndex(where: { $0.id == current }) else {
            selectedAnnotationID = pending[0].id
            return
        }
        selectedAnnotationID = pending[(currentIndex + 1) % pending.count].id
    }

    // MARK: - 編集

    /// 既存Boxの大きさに合わせた既定サイズ。中央固定の使いにくさを避ける。
    var defaultRectSize: CGSize {
        guard !annotations.isEmpty else {
            return CGSize(
                width: NormalizedRect.centeredDefault.width,
                height: NormalizedRect.centeredDefault.height
            )
        }
        let widths = annotations.map(\.rect.width).sorted()
        let heights = annotations.map(\.rect.height).sorted()
        return CGSize(
            width: widths[widths.count / 2],
            height: heights[heights.count / 2]
        )
    }

    func addAnnotation() {
        addAnnotation(atNormalizedCenter: CGPoint(x: 0.5, y: 0.5))
    }

    func addAnnotation(atNormalizedCenter center: CGPoint) {
        recordHistory()
        let size = defaultRectSize
        let annotation = Annotation(
            denomination: selectedAnnotation?.denomination ?? .one,
            rect: NormalizedRect(
                centerX: Double(center.x),
                centerY: Double(center.y),
                width: Double(size.width),
                height: Double(size.height)
            ).clamped()
        )
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        Haptics.impact()
    }

    func deleteSelected() {
        guard let selectedAnnotationID else { return }
        recordHistory()
        annotations.removeAll(where: { $0.id == selectedAnnotationID })
        self.selectedAnnotationID = annotations.first?.id
        Haptics.warning()
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        annotations = previous
        if let selectedAnnotationID,
           !annotations.contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = annotations.first?.id
        }
        Haptics.impact()
    }

    func confirmSelected() {
        guard let index = selectedIndex else { return }
        annotations[index].needsReview = false
        Haptics.selection()
    }

    /// 残りの要確認をまとめて確定する。すべて目視済みのときだけ使う。
    func confirmAll() {
        guard hasPendingReview else { return }
        recordHistory()
        for index in annotations.indices {
            annotations[index].needsReview = false
        }
        Haptics.success()
    }

    func move(
        id: UUID,
        from initialRect: NormalizedRect,
        displayTranslation: CGSize,
        viewportScale: CGFloat,
        converter: AspectFitCoordinateConverter
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let translation = converter.normalizedTranslation(
            for: displayTranslation,
            viewportScale: viewportScale
        )
        annotations[index].rect = NormalizedRect(
            centerX: initialRect.centerX + translation.width,
            centerY: initialRect.centerY + translation.height,
            width: initialRect.width,
            height: initialRect.height
        ).clamped()
    }

    func resize(
        id: UUID,
        from initialRect: NormalizedRect,
        at handle: BoundingBoxResizeHandle,
        displayTranslation: CGSize,
        viewportScale: CGFloat,
        converter: AspectFitCoordinateConverter
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let translation = converter.normalizedTranslation(
            for: displayTranslation,
            viewportScale: viewportScale
        )
        annotations[index].rect = initialRect.resized(at: handle, by: translation)
    }

    /// ドラッグ開始時に一度だけ呼び、移動・リサイズ全体を1手として取り消せるようにする。
    func beginInteractiveEdit() {
        recordHistory()
    }

    // MARK: - 保存

    func save() async -> Bool {
        guard imageSize.width > 0, imageSize.height > 0 else {
            present(kind: .validation, title: "保存できません", message: "画像を読み込めませんでした。")
            return false
        }
        guard annotations.allSatisfy({ $0.rect.isValid }) else {
            present(
                kind: .validation,
                title: "保存できません",
                message: "画像の外にはみ出した、または大きさが0のBounding Boxがあります。"
            )
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            if let existingImageID = draft.existingImageID {
                _ = try await service.updateAnnotations(
                    imageID: existingImageID,
                    annotations: annotations,
                    reviewStatus: .reviewed
                )
            } else {
                _ = try await service.upload(
                    imageData: draft.imageData,
                    metadata: DatasetImageUploadMetadata(
                        source: draft.source,
                        captureSessionID: draft.captureSessionID,
                        reviewStatus: .reviewed,
                        annotations: annotations,
                        modelVersionUsedForPreAnnotation: draft.modelVersionUsedForPreAnnotation
                    )
                )
            }
            Haptics.success()
            return true
        } catch {
            self.error = AppError(error, title: "保存できませんでした")
            Haptics.failure()
            return false
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private

    private var selectedIndex: Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex(where: { $0.id == selectedAnnotationID })
    }

    private func recordHistory() {
        history.append(annotations)
        if history.count > historyLimit {
            history.removeFirst()
        }
    }

    private func present(kind: AppError.Kind, title: String, message: String) {
        error = AppError(kind: kind, title: title, message: message)
        Haptics.failure()
    }
}
