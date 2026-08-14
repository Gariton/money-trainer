import Foundation

enum TrainingJobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case preparing
    case uploading
    case validating
    case training
    case evaluating
    case exportingCoreML = "exporting_core_ml"
    case validatingCoreML = "validating_core_ml"
    case completed
    case failed
    case unknown

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .preparing: "Preparing"
        case .uploading: "Uploading"
        case .validating: "Validating"
        case .training: "Training"
        case .evaluating: "Evaluating"
        case .exportingCoreML: "Exporting Core ML"
        case .validatingCoreML: "Validating Core ML"
        case .completed: "Completed"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = TrainingJobStatus(rawValue: value) ?? .unknown
    }
}
