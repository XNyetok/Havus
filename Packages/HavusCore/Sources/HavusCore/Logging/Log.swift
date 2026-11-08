import os

/// Havus's lines in the unified log, where Console, `log show` and a problem report find them.
///
/// The log says what Havus did and why: what a scan found, why `PathGuard` refused a path, which error a removal ran
/// into, what launchctl answered. Paths and the names of the user's apps and agents are logged as
/// `.private(mask: .hash)`, which shows a hash that's the same for the same value, so the lines about one file can be
/// matched up without revealing it. Counts, sizes, durations, rule IDs, reasons and error codes are public.
///
/// macOS keeps `notice`, `error` and `fault` lines on disk for a few days, `info` lines only in memory unless an error
/// follows, and `debug` lines not at all. So whatever helps after the fact is a `notice` or above.
public enum Log {
    public static let subsystem = "id.nyetok.havus"

    /// Launches, permissions and the exclusion list.
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// What the scans found.
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    /// What went to the Trash, and what didn't and why.
    public static let removal = Logger(subsystem: subsystem, category: "removal")
    /// Turning launch agents off and on, and moving them to the Trash.
    public static let launchd = Logger(subsystem: subsystem, category: "launchd")
    /// The update check.
    public static let updates = Logger(subsystem: subsystem, category: "updates")
    /// Crash reports and problem reports.
    public static let reports = Logger(subsystem: subsystem, category: "reports")

    /// Sizes go in the log in megabytes, as `\(Log.megabytes(size), format: .fixed(precision: 1)) MB`: easier to read
    /// than bytes, and written the same whatever the user's language.
    public static func megabytes(_ bytes: Int64) -> Double {
        Double(bytes) / 1_000_000
    }
}
