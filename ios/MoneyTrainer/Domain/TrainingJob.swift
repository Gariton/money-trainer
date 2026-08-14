import Foundation

struct TrainingJob: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let modelVersion: String?
    let status: TrainingJobStatus
    let phase: String?
    let progress: Double
    let validationIssues: [TrainingValidationIssue]
    let errorMessage: String?
    let createdAt: Date
    let updatedAt: Date?

    var normalizedProgress: Double { min(max(progress > 1 ? progress / 100 : progress, 0), 1) }

    var stageDisplayName: String {
        guard let phase, !phase.isEmpty else { return status.displayName }
        return phase.replacing("_", with: " ").capitalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case modelVersion = "model_version"
        case status
        case phase
        case progress
        case validationIssues = "validation_errors"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        modelVersion: String?,
        status: TrainingJobStatus,
        phase: String?,
        progress: Double,
        validationIssues: [TrainingValidationIssue],
        errorMessage: String?,
        createdAt: Date,
        updatedAt: Date?
    ) {
        self.id = id
        self.modelVersion = modelVersion
        self.status = status
        self.phase = phase
        self.progress = progress
        self.validationIssues = validationIssues
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion)
        status = try container.decode(TrainingJobStatus.self, forKey: .status)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        if let issues = try? container.decode(
            [TrainingValidationIssue].self,
            forKey: .validationIssues
        ) {
            validationIssues = issues
        } else {
            let messages = try container.decodeIfPresent([String].self, forKey: .validationIssues) ?? []
            validationIssues = messages.map { TrainingValidationIssue(code: "validation", message: $0) }
        }
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
