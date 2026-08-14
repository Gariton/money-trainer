import Foundation
@testable import MoneyTrainer

struct MockModelService: ModelServiceProtocol {
    var records: [ModelRecord] = []

    func models() async throws -> [ModelRecord] { records }
    func latest() async throws -> ModelRecord { records[0] }
    func model(id: String) async throws -> ModelRecord { records.first(where: { $0.id == id }) ?? records[0] }
    func download(id: String) async throws -> Data { Data() }
    func reports(modelID: String) async throws -> [FailureReportItem] { [] }
    func reportData(item: FailureReportItem) async throws -> Data { Data() }
}
