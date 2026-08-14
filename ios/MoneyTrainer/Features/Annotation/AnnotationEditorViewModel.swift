import Observation
import SwiftUI

@MainActor
@Observable
final class AnnotationEditorViewModel {
    let draft: AnnotationDraft
    let image: UIImage
    let imageSize: CGSize

    var annotations: [Annotation]
    var selectedAnnotationID: UUID?
    var isSaving = false
    var isShowingError = false
    var errorMessage = ""

    @ObservationIgnored private let service: any DatasetServiceProtocol

    init(draft: AnnotationDraft, service: any DatasetServiceProtocol) {
        self.draft = draft
        self.service = service
        let decodedImage = UIImage(data: draft.imageData) ?? UIImage()
        image = decodedImage
        imageSize = decodedImage.size
        annotations = draft.annotations
        selectedAnnotationID = draft.annotations.first?.id
    }

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

    func addAnnotation() {
        let annotation = Annotation(
            denomination: selectedAnnotation?.denomination ?? .one,
            rect: .centeredDefault
        )
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
    }

    func select(_ id: UUID) {
        selectedAnnotationID = id
    }

    func deleteSelected() {
        guard let selectedAnnotationID else { return }
        annotations.removeAll(where: { $0.id == selectedAnnotationID })
        self.selectedAnnotationID = annotations.first?.id
    }

    func move(
        id: UUID,
        from initialRect: NormalizedRect,
        displayTranslation: CGSize,
        converter: AspectFitCoordinateConverter
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let translation = converter.normalizedTranslation(for: displayTranslation)
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
        displayTranslation: CGSize,
        converter: AspectFitCoordinateConverter
    ) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var displayRect = converter.displayRect(for: initialRect)
        displayRect.size.width += displayTranslation.width
        displayRect.size.height += displayTranslation.height
        displayRect.size.width = max(displayRect.width, DesignTokens.minimumTapSize)
        displayRect.size.height = max(displayRect.height, DesignTokens.minimumTapSize)
        annotations[index].rect = converter.normalizedRect(from: displayRect)
    }

    func save() async -> Bool {
        guard imageSize.width > 0, imageSize.height > 0 else {
            showError("画像を読み込めませんでした。")
            return false
        }
        guard annotations.allSatisfy({ $0.rect.isValid }) else {
            showError("画像外または無効なBounding Boxがあります。")
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
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
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    private var selectedIndex: Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex(where: { $0.id == selectedAnnotationID })
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
