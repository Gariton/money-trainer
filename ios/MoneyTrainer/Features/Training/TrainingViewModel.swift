import Foundation
import Observation

@MainActor
@Observable
final class TrainingViewModel {
    private(set) var jobs: [TrainingJob] = []
    private(set) var isLoading = false
    private(set) var isStarting = false
    var mockMode = false
    var isShowingError = false
    var errorMessage = ""

    @ObservationIgnored private let service: any TrainingServiceProtocol
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let activeJobIDsKey = "training.activeJobIDs"

    init(service: any TrainingServiceProtocol, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var activeJobIDs: [String] {
        jobs.filter { !$0.status.isTerminal }.map(\.id).sorted()
    }

    func monitor() async {
        await refresh(showLoading: true)
        while !Task.isCancelled {
            let hasActiveJob = jobs.contains(where: { !$0.status.isTerminal })
                || !(defaults.stringArray(forKey: activeJobIDsKey) ?? []).isEmpty
            guard hasActiveJob else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            await refresh(showLoading: false)
        }
    }

    func refresh(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }
        do {
            jobs = try await service.jobs().sorted(by: { $0.createdAt > $1.createdAt })
            persistActiveJobs()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func startTraining() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let job = try await service.start(mockMode: mockMode)
            jobs.insert(job, at: 0)
            persistActiveJobs()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func clearError() {
        isShowingError = false
        errorMessage = ""
    }

    private func persistActiveJobs() {
        defaults.set(activeJobIDs, forKey: activeJobIDsKey)
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
