import SwiftUI
import SwiftData

@main
struct CatVoxApp: App {

    @State private var quotaStore = ScanQuotaStore()

    init() {
        AnalyticsService.configure()
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
