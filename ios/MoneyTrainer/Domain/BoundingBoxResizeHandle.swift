import CoreGraphics
import Foundation

enum BoundingBoxResizeHandle: CaseIterable, Hashable, Identifiable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var horizontalSign: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: -1
        case .topRight, .bottomRight: 1
        }
    }

    var verticalSign: CGFloat {
        switch self {
        case .topLeft, .topRight: -1
        case .bottomLeft, .bottomRight: 1
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeft: "左上のリサイズハンドル"
        case .topRight: "右上のリサイズハンドル"
        case .bottomLeft: "左下のリサイズハンドル"
        case .bottomRight: "右下のリサイズハンドル"
        }
    }

    func diagonalTranslation(distance: CGFloat) -> CGSize {
        CGSize(
            width: horizontalSign * distance,
            height: verticalSign * distance
        )
    }
}
