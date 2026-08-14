import Foundation

enum DatasetSource: String, Codable, CaseIterable, Sendable {
    case camera
    case photoLibrary = "photo_library"
    case liveTest = "live_test"

    var displayName: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photo Library"
        case .liveTest: "Live Test"
        }
    }
}
