import CoreML
import Foundation

actor ModelCompiler {
    func compileAndValidate(sourceURL: URL) async throws -> URL {
        let compiledURL = try await MLModel.compileModel(at: sourceURL)
        let configuration = MLModelConfiguration()
        _ = try await MLModel.load(contentsOf: compiledURL, configuration: configuration)
        return compiledURL
    }
}
