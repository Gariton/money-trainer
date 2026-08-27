import Observation

/// サーバー接続状態をアプリ全体で共有する。
/// 各画面が失敗して初めて気づく、という状態をなくすために使う。
@MainActor
@Observable
final class ConnectionMonitor {
    enum State: Equatable {
        case unknown
        case checking
        case connected(imageCount: Int)
        case failed(AppError)

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    private(set) var state: State = .unknown

    @ObservationIgnored private var service: any DatasetServiceProtocol
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    init(service: any DatasetServiceProtocol) {
        self.service = service
    }

    var failure: AppError? {
        if case let .failed(error) = state { return error }
        return nil
    }

    var summary: String {
        switch state {
        case .unknown: "未確認"
        case .checking: "確認中"
        case let .connected(imageCount): "接続済み・画像\(imageCount)件"
        case let .failed(error): error.title
        }
    }

    /// 入力の途中で走らせないよう、呼び出し側で間隔を空けて使う。
    func check() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            guard let self else { return }
            state = .checking
            do {
                let stats = try await service.stats()
                guard !Task.isCancelled else { return }
                state = .connected(imageCount: stats.imageCount)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(AppError(error))
            }
        }
    }

    func checkAndWait() async {
        check()
        await checkTask?.value
    }

    /// 他画面での成功を接続状態へ反映し、無駄な再確認を避ける。
    func noteSuccess() {
        if state.isFailed || state == .unknown {
            check()
        }
    }

    func noteFailure(_ error: AppError) {
        if error.kind == .connection || error.kind == .authentication {
            state = .failed(error)
        }
    }
}
