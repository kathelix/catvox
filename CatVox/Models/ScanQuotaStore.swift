import Foundation
import Observation

/// Client-side mirror of the server's daily scan quota.
///
/// The server remains the enforcement authority (returns HTTP 429 when the
/// limit is reached). This store tracks usage locally so the home screen
/// can show a live countdown and gate new scans without a round-trip.
///
/// Usage is counted per UTC calendar day, so it resets at 00:00 UTC whatever
/// the device's time zone. That is the same day the server counts in
/// usageGuard.ts (`todayUTC()`, stored as `lastResetDate`).
@MainActor
@Observable
final class ScanQuotaStore {

    static let dailyLimit = 5

    private(set) var scansRemaining: Int

    private let defaults: UserDefaults
    private let now: () -> Date
    /// The UTC quota day that `scansRemaining` was computed for.
    @ObservationIgnored private var countedDay: String

    init(
        initialScansRemaining: Int? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.now = now
        Self.dropLegacyLocalDateUsage(in: defaults)

        let today = Self.quotaDay(for: now())
        countedDay = today
        scansRemaining = initialScansRemaining ?? Self.remaining(on: today, in: defaults)
    }

    /// Call after a successful analysis completes.
    func recordScan() {
        let today = Self.quotaDay(for: now())
        let used = min(Self.used(on: today, in: defaults) + 1, Self.dailyLimit)
        persist(used: used, on: today)
    }

    /// Call when the server returns HTTP 429 — sync to the hard limit.
    func markExhausted() {
        persist(used: Self.dailyLimit, on: Self.quotaDay(for: now()))
    }

    /// Recomputes `scansRemaining` if the UTC day has changed since it was
    /// last computed. The app process can outlive a day in the background,
    /// so call this when the app becomes active and before gating a scan.
    func refreshIfNewDay() {
        let today = Self.quotaDay(for: now())
        guard today != countedDay else { return }
        countedDay = today
        scansRemaining = Self.remaining(on: today, in: defaults)
    }

    /// The UTC calendar day that `date` falls in, as `yyyy-MM-dd`: the same
    /// value the server derives with `new Date().toISOString().slice(0, 10)`.
    nonisolated static func quotaDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Private

    private enum Keys {
        static let used = "catvox.scansUsedToday"
        static let day  = "catvox.lastScanDateUTC"
        /// Device-local date written by builds that counted local days.
        static let legacyLocalDate = "catvox.lastScanDate"
    }

    nonisolated static func resetPersistedUsageForUITesting() {
        UserDefaults.standard.removeObject(forKey: Keys.used)
        UserDefaults.standard.removeObject(forKey: Keys.day)
        UserDefaults.standard.removeObject(forKey: Keys.legacyLocalDate)
    }

    /// Older builds stored the count under a device-local date, which can't
    /// be mapped to a UTC day. Read as a UTC date, a count saved just after
    /// local midnight east of UTC would block the user for a whole UTC day
    /// after the server had reset. Drop the pair instead; the server still
    /// enforces the real limit.
    private static func dropLegacyLocalDateUsage(in defaults: UserDefaults) {
        guard defaults.object(forKey: Keys.legacyLocalDate) != nil else { return }
        defaults.removeObject(forKey: Keys.legacyLocalDate)
        defaults.removeObject(forKey: Keys.used)
    }

    private static func used(on day: String, in defaults: UserDefaults) -> Int {
        guard defaults.string(forKey: Keys.day) == day else { return 0 }
        return defaults.integer(forKey: Keys.used)
    }

    private static func remaining(on day: String, in defaults: UserDefaults) -> Int {
        max(0, dailyLimit - used(on: day, in: defaults))
    }

    private func persist(used: Int, on day: String) {
        defaults.set(used, forKey: Keys.used)
        defaults.set(day,  forKey: Keys.day)
        countedDay = day
        scansRemaining = max(0, Self.dailyLimit - used)
    }
}
