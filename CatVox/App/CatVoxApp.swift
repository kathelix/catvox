import SwiftUI
import SwiftData
import PostHog

enum PostHogEnv: String {
    case projectToken = "POSTHOG_PROJECT_TOKEN"
    case host = "POSTHOG_HOST"

    var value: String {
        guard let v = ProcessInfo.processInfo.environment[rawValue] else {
            fatalError("Set \(rawValue) in the Xcode scheme environment variables.")
        }
        return v
    }
}

@main
struct CatVoxApp: App {

    @State private var quotaStore = ScanQuotaStore()

    init() {
        let config = PostHogConfig(apiKey: PostHogEnv.projectToken.value, host: PostHogEnv.host.value)
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)

        Self.prepareApplicationSupportDirectory()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(quotaStore)
        }
        .modelContainer(for: SavedScan.self)
    }

    private static func prepareApplicationSupportDirectory() {
        let fileManager = FileManager.default
        guard let supportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return
        }

        try? fileManager.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
    }
}
