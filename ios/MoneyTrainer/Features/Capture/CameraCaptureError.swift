import Foundation

enum CameraCaptureError: LocalizedError, Sendable {
    case permissionDenied
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case invalidPhotoData

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "カメラへのアクセスが許可されていません。"
        case .cameraUnavailable: "利用可能なカメラが見つかりません。"
        case .cannotAddInput: "カメラ入力を開始できません。"
        case .cannotAddOutput: "写真出力を開始できません。"
        case .invalidPhotoData: "撮影した画像を読み込めませんでした。"
        }
    }
}
