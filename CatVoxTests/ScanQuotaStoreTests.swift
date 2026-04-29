import XCTest
@testable import CatVox

final class ScanQuotaStoreTests: XCTestCase {
    private let usedKey = "catvox.scansUsedToday"
    private let lastDateKey = "catvox.lastScanDate"

    override func setUp() {
        super.setUp()
        clearQuotaDefaults()
    }

    override func tearDown() {
        clearQuotaDefaults()
        super.tearDown()
    }

    @MainActor
    func testInitialStoreUsesFullDailyLimitWhenNoUsageExists() {
        let store = ScanQuotaStore()

        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
    }

    @MainActor
    func testRecordScanDecrementsRemainingScansAndClampsAtZero() {
        let store = ScanQuotaStore()

        for _ in 0..<(ScanQuotaStore.dailyLimit + 2) {
            store.recordScan()
        }

        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: usedKey),
            ScanQuotaStore.dailyLimit
        )
        XCTAssertEqual(UserDefaults.standard.string(forKey: lastDateKey), todayString())
    }

    @MainActor
    func testMarkExhaustedSynchronizesLocalStateWithServerLimit() {
        let store = ScanQuotaStore()

        store.markExhausted()

        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: usedKey),
            ScanQuotaStore.dailyLimit
        )
        XCTAssertEqual(UserDefaults.standard.string(forKey: lastDateKey), todayString())
    }

    @MainActor
    func testRecordScanResetsStaleUsageBeforeIncrementing() {
        UserDefaults.standard.set(4, forKey: usedKey)
        UserDefaults.standard.set("1999-12-31", forKey: lastDateKey)

        let store = ScanQuotaStore()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)

        store.recordScan()

        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit - 1)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: usedKey), 1)
        XCTAssertEqual(UserDefaults.standard.string(forKey: lastDateKey), todayString())
    }

    private func clearQuotaDefaults() {
        UserDefaults.standard.removeObject(forKey: usedKey)
        UserDefaults.standard.removeObject(forKey: lastDateKey)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
