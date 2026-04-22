import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .environment(ScanQuotaStore())
        .modelContainer(for: SavedScan.self, inMemory: true)
}
