import Foundation

enum CoinDenomination: String, Codable, CaseIterable, Identifiable, Sendable {
    case one = "jpy_1"
    case five = "jpy_5"
    case ten = "jpy_10"
    case fifty = "jpy_50"
    case oneHundred = "jpy_100"
    case fiveHundred = "jpy_500"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .one: "1円"
        case .five: "5円"
        case .ten: "10円"
        case .fifty: "50円"
        case .oneHundred: "100円"
        case .fiveHundred: "500円"
        }
    }

    var value: Int {
        switch self {
        case .one: 1
        case .five: 5
        case .ten: 10
        case .fifty: 50
        case .oneHundred: 100
        case .fiveHundred: 500
        }
    }
}
