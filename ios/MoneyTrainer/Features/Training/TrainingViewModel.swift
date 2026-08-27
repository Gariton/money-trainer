import Foundation
import Observation

@MainActor
@Observable
final class TrainingViewModel {
    private(set) var jobs: [TrainingJob] = []
    private(set) var isLoading = false
    private(set) var isStarting = false
    var error: AppError?

    @ObservationIgnored private let service: any TrainingServiceProtocol
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let developerSettings: DeveloperSettings
    @ObservationIgnored private let activeJobIDsKey = "training.activeJobIDs"
    /// 通知を一度だけ出すために、終了済みとして扱ったJobを覚えておく。
    @ObservationIgnored private var notifiedJobIDs: Set<String> = []

    init(
        service: any TrainingServiceProtocol,
        defaults: UserDefaults = .standard,
        developerSettings: DeveloperSettings? = nil
    ) {
        self.service = service
        self.defaults = defaults
        self.developerSettings = developerSettings ?? DeveloperSettings(defaults: defaults)
    }

    var activeJobIDs: [String] {
        jobs.filter { !$0.status.isTerminal }.map(\.id).sorted()
    }

    /// 進行中のJobは1件だけ画面上部で大きく扱う。
    var activeJob: TrainingJob? {
        jobs.first(where: { !$0.status.isTerminal })
    }

    var finishedJobs: [TrainingJob] {
        jobs.filter(\.status.isTerminal)
    }

    var isMockTrainingEnabled: Bool { developerSettings.isMockTrainingEnabled }

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
            let previouslyActive = Set(activeJobIDs)
            jobs = try await service.jobs().sorted(by: { $0.createdAt > $1.createdAt })
            error = nil
            persistActiveJobs()
            await notifyNewlyFinishedJobs(previouslyActive: previouslyActive)
        } catch {
            present(error)
        }
    }

    func startTraining() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let job = try await service.start(mockMode: developerSettings.isMockTrainingEnabled)
            // 通知の許可は、実際にJobを始めて待つ意味が生まれた瞬間にだけ尋ねる。
            await TrainingCompletionNotifier.requestAuthorizationIfNeeded()
            jobs.insert(job, at: 0)
            error = nil
            persistActiveJobs()
            Haptics.success()
        } catch {
            present(error)
            Haptics.failure()
        }
    }

    func present(_ error: any Error) {
        self.error = AppError(error, title: "学習を実行できません")
    }

    func clearError() {
        error = nil
    }

    private func notifyNewlyFinishedJobs(previouslyActive: Set<String>) async {
        for job in jobs
        where job.status.isTerminal
            && previouslyActive.contains(job.id)
            && !notifiedJobIDs.contains(job.id) {
            notifiedJobIDs.insert(job.id)
            await TrainingCompletionNotifier.notify(job: job)
            if job.status == .completed {
                Haptics.success()
            } else {
                Haptics.failure()
            }
        }
    }

    private func persistActiveJobs() {
        defaults.set(activeJobIDs, forKey: activeJobIDsKey)
    }
}
