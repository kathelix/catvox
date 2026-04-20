import SwiftUI

@main
struct CatVoxApp: App {

    @State private var quotaStore = ScanQuotaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(quotaStore)
        }
    }
}
