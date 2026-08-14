import Foundation

enum ModelManagerError: LocalizedError, Sendable {
    case compiledModelMissing

    var errorDescription: String? {
        switch self {
        case .compiledModelMissing: "コンパイル済みCore MLモデルが見つかりません。"
        }
    }
}
