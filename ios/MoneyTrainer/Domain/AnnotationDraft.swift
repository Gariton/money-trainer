import Foundation

struct AnnotationDraft: Identifiable, Sendable {
    let id: UUID
    let imageData: Data
    let source: DatasetSource
    let captureSessionID: String
    var annotations: [Annotation]
    let modelVersionUsedForPreAnnotation: String?
    /// 既存のDataset画像を編集するときだけ入る。nilなら新規アップロード。
    let existingImageID: String?

    init(
        id: UUID = UUID(),
        imageData: Data,
        source: DatasetSource,
        captureSessionID: String,
        annotations: [Annotation] = [],
        modelVersionUsedForPreAnnotation: String? = nil,
        existingImageID: String? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.source = source
        self.captureSessionID = captureSessionID
        self.annotations = annotations
        self.modelVersionUsedForPreAnnotation = modelVersionUsedForPreAnnotation
        self.existingImageID = existingImageID
    }

    var isEditingExistingImage: Bool { existingImageID != nil }
}
