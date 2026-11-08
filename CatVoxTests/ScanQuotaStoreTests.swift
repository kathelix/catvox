import XCTest
@testable import CatVox

final class ScanQuotaStoreTests: XCTestCase {
    private let usedKey = "catvox.scansUsedToday"
    private let dayKey = "catvox.lastScanDateUTC"
    private let legacyLocalDateKey = "catvox.lastScanDate"
    private let suiteName = "CatVoxTests.ScanQuotaStoreTests"

    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!               // UTC+9, no DST
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")! // UTC-8 in January
    private let london = TimeZone(identifier: "Europe/London")!           // UTC+1 in July (BST)

    private var defaults: UserDefaults!
    private var originalDefaultTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        // Tests stand in for a device's time zone by setting NSTimeZone.default,
        // which a DateFormatter without an explicit timeZone follows.
        originalDefaultTimeZone = NSTimeZone.default
    }

    override func tearDown() {
        NSTimeZone.default = originalDefaultTimeZone
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Same UTC day

    @MainActor
    func testInitialStoreUsesFullDailyLimitWhenNoUsageExists() {
        let store = makeStore(clock: TestClock(time(2026, 11, 7, 12, 0, in: utc)))

        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
    }

    @MainActor
    func testRecordScanDecrementsRemainingScansAndClampsAtZero() {
        let store = makeStore(clock: TestClock(time(2026, 11, 7, 12, 0, in: utc)))

        for _ in 0..<(ScanQuotaStore.dailyLimit + 2) {
            store.recordScan()
        }

        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(defaults.integer(forKey: usedKey), ScanQuotaStore.dailyLimit)
        XCTAssertEqual(defaults.string(forKey: dayKey), "2026-11-07")
    }

    @MainActor
    func testUsageCarriesAcrossRefreshAndRelaunchWithinTheSameUTCDay() {
        let clock = TestClock(time(2026, 11, 7, 0, 0, in: utc))
        let store = makeStore(clock: clock)
        store.recordScan()
        store.recordScan()

        clock.now = time(2026, 11, 7, 23, 59, 59, in: utc)
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit - 2)

        let relaunched = makeStore(clock: clock)
        XCTAssertEqual(relaunched.scansRemaining, ScanQuotaStore.dailyLimit - 2)

        relaunched.recordScan()
        XCTAssertEqual(relaunched.scansRemaining, ScanQuotaStore.dailyLimit - 3)
        XCTAssertEqual(defaults.integer(forKey: usedKey), 3)
    }

    @MainActor
    func testMarkExhaustedSynchronizesLocalStateWithServerLimit() {
        let store = makeStore(clock: TestClock(time(2026, 11, 7, 12, 0, in: utc)))

        store.markExhausted()

        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(defaults.integer(forKey: usedKey), ScanQuotaStore.dailyLimit)
        XCTAssertEqual(defaults.string(forKey: dayKey), "2026-11-07")
    }

    @MainActor
    func testRecordScanResetsStaleUsageBeforeIncrementing() {
        defaults.set(4, forKey: usedKey)
        defaults.set("1999-12-31", forKey: dayKey)

        let store = makeStore(clock: TestClock(time(2026, 11, 7, 12, 0, in: utc)))
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)

        store.recordScan()

        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit - 1)
        XCTAssertEqual(defaults.integer(forKey: usedKey), 1)
        XCTAssertEqual(defaults.string(forKey: dayKey), "2026-11-07")
    }

    // MARK: - Day boundary is 00:00 UTC in every device time zone

    func testQuotaDayIsTheUTCCalendarDayInEveryDeviceTimeZone() {
        let lastSecond = time(2026, 11, 7, 23, 59, 59, in: utc)
        let firstSecond = time(2026, 11, 8, 0, 0, 0, in: utc)

        for zone in [utc, tokyo, losAngeles, london] {
            NSTimeZone.default = zone
            XCTAssertEqual(ScanQuotaStore.quotaDay(for: lastSecond), "2026-11-07", zone.identifier)
            XCTAssertEqual(ScanQuotaStore.quotaDay(for: firstSecond), "2026-11-08", zone.identifier)
        }
    }

    @MainActor
    func testEastOfUTCUsageCarriesPastLocalMidnightAndResetsAtUTCMidnight() {
        // Tokyo's midnight comes 9 hours before UTC midnight.
        NSTimeZone.default = tokyo
        let clock = TestClock(time(2026, 11, 7, 23, 50, in: tokyo))   // 14:50 UTC, 7 Nov
        let store = makeStore(clock: clock)
        exhaust(store)

        // Past local midnight, but the server is still on 7 Nov.
        clock.now = time(2026, 11, 8, 0, 10, in: tokyo)               // 15:10 UTC, 7 Nov
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(makeStore(clock: clock).scansRemaining, 0)

        clock.now = time(2026, 11, 8, 8, 59, 59, in: tokyo)           // 23:59:59 UTC, 7 Nov
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, 0)

        // The server resets at 09:00 in Tokyo, and so does the app.
        clock.now = time(2026, 11, 8, 9, 0, in: tokyo)                // 00:00 UTC, 8 Nov
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
        XCTAssertEqual(makeStore(clock: clock).scansRemaining, ScanQuotaStore.dailyLimit)
    }

    @MainActor
    func testWestOfUTCUsageResetsAtUTCMidnightNotLocalMidnight() {
        // UTC midnight is 16:00 in Los Angeles in January.
        NSTimeZone.default = losAngeles
        let clock = TestClock(time(2026, 1, 15, 9, 0, in: losAngeles))    // 17:00 UTC, 15 Jan
        let store = makeStore(clock: clock)
        exhaust(store)

        clock.now = time(2026, 1, 15, 15, 59, 59, in: losAngeles)         // 23:59:59 UTC, 15 Jan
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, 0)

        // The server has reset; the app must not wait for local midnight.
        clock.now = time(2026, 1, 15, 16, 0, in: losAngeles)              // 00:00 UTC, 16 Jan
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
        store.recordScan()

        // Local midnight falls inside UTC 16 Jan, so it resets nothing.
        clock.now = time(2026, 1, 16, 0, 10, in: losAngeles)              // 08:10 UTC, 16 Jan
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit - 1)
        XCTAssertEqual(makeStore(clock: clock).scansRemaining, ScanQuotaStore.dailyLimit - 1)
    }

    @MainActor
    func testMarkExhaustedJustAfterLocalMidnightOnlyBlocksUntilUTCMidnight() {
        // A 429 between London's midnight and UTC midnight belongs to the
        // server day that is about to end.
        NSTimeZone.default = london
        let clock = TestClock(time(2026, 7, 16, 0, 30, in: london))   // 23:30 UTC, 15 Jul
        let store = makeStore(clock: clock)

        store.markExhausted()

        XCTAssertEqual(store.scansRemaining, 0)
        XCTAssertEqual(defaults.string(forKey: dayKey), "2026-07-15")

        clock.now = time(2026, 7, 16, 0, 59, 59, in: london)          // 23:59:59 UTC, 15 Jul
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, 0)

        clock.now = time(2026, 7, 16, 1, 0, in: london)               // 00:00 UTC, 16 Jul
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
        XCTAssertEqual(makeStore(clock: clock).scansRemaining, ScanQuotaStore.dailyLimit)
    }

    @MainActor
    func testRefreshKeepsInitialValueUntilTheUTCDayChanges() {
        // -forceQuotaExceeded launches with an initial 0 and no stored usage.
        let clock = TestClock(time(2026, 11, 7, 10, 0, in: utc))
        let store = makeStore(clock: clock, initialScansRemaining: 0)

        clock.now = time(2026, 11, 7, 23, 59, 59, in: utc)
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, 0)

        clock.now = time(2026, 11, 8, 0, 0, in: utc)
        store.refreshIfNewDay()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
    }

    // MARK: - Upgrade from builds that counted device-local days

    @MainActor
    func testLegacyLocalDateUsageIsDroppedSoItCannotBlockAUTCDay() {
        // An older build in London stored an exhausted count under the local
        // date 16 Jul after a 429 at 00:30 BST (23:30 UTC on 15 Jul). Read as
        // a UTC date, it would block all of 16 Jul UTC.
        defaults.set(ScanQuotaStore.dailyLimit, forKey: usedKey)
        defaults.set("2026-07-16", forKey: legacyLocalDateKey)
        NSTimeZone.default = london

        let store = makeStore(clock: TestClock(time(2026, 7, 16, 1, 30, in: london))) // 00:30 UTC, 16 Jul

        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit)
        XCTAssertNil(defaults.object(forKey: legacyLocalDateKey))
        XCTAssertNil(defaults.object(forKey: usedKey))

        store.recordScan()
        XCTAssertEqual(store.scansRemaining, ScanQuotaStore.dailyLimit - 1)
    }

    // MARK: - Helpers

    private final class TestClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    @MainActor
    private func makeStore(clock: TestClock, initialScansRemaining: Int? = nil) -> ScanQuotaStore {
        ScanQuotaStore(
            initialScansRemaining: initialScansRemaining,
            defaults: defaults,
            now: { clock.now }
        )
    }

    @MainActor
    private func exhaust(_ store: ScanQuotaStore) {
        for _ in 0..<ScanQuotaStore.dailyLimit {
            store.recordScan()
        }
        XCTAssertEqual(store.scansRemaining, 0)
    }

    /// The instant a clock set to `zone` shows as this wall-clock time.
    private func time(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int = 0,
        in zone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!
    }
}
