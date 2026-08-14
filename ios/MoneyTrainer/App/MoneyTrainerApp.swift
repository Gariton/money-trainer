import SwiftUI

@main
struct MoneyTrainerApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
        }
    }
}
