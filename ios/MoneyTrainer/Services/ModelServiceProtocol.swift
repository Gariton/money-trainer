import Foundation

protocol ModelServiceProtocol: Sendable {
    func models() async throws -> [ModelRecord]
    func latest() async throws -> ModelRecord
    func model(id: String) async throws -> ModelRecord
    func download(id: String) async throws -> Data
    func reports(modelID: String) async throws -> [FailureReportItem]
    func reportData(item: FailureReportItem) async throws -> Data
}
