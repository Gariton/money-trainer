import UserNotifications

/// 学習の完了を、画面を開いていなくても受け取れるようにする。
/// これまではTraining画面を表示している間しか進行が分からなかった。
enum TrainingCompletionNotifier {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func notify(job: TrainingJob) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        switch job.status {
        case .completed:
            content.title = "学習が完了しました"
            content.body = job.modelVersion.map { "モデル \($0) を配布できます。" }
                ?? "新しいモデルが登録されました。"
        case .failed:
            content.title = "学習に失敗しました"
            content.body = job.errorMessage ?? "Training画面で詳細を確認してください。"
        default:
            return
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "training-\(job.id)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
