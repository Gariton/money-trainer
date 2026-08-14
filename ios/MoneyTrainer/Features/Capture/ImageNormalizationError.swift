import Foundation

enum ImageNormalizationError: LocalizedError, Sendable {
    case unsupportedImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: "選択した画像形式を読み込めません。"
        case .encodingFailed: "画像をJPEGへ変換できません。"
        }
    }
}
