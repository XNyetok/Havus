import Foundation
import OSLog

/// Havus's own log lines as text, for a problem report.
///
/// Lines from an earlier session, such as the one that crashed, need the whole log store (`OSLogStore` with the
/// system scope), which macOS opens only for admin accounts outside the sandbox. For other accounts, only the running
/// session's lines can be read.
public enum LogExport {
    /// The lines of `process` between `start` and `end`, oldest first: the last `limit` of them.
    public static func lines(
        of process: String, from start: Date, to end: Date, subsystem: String = Log.subsystem, limit: Int = 1_000
    ) -> [String] {
        guard let store = (try? OSLogStore(scope: .system)) ?? (try? OSLogStore(scope: .currentProcessIdentifier))
        else {
            Log.reports.error("Couldn't open the log store")
            return []
        }
        let predicate = NSPredicate(format: "subsystem == %@ AND process == %@", subsystem, process)
        guard let entries = try? store.getEntries(at: store.position(date: start), matching: predicate) else {
            return []
        }
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            if entry.date > end { break }
            lines.append(
                line(date: entry.date, level: name(of: entry.level), category: entry.category, entry.composedMessage))
        }
        return Array(lines.suffix(limit))
    }

    /// Writes `lines` to `Havus-log-<end>.txt` in `folder`, under a header that says which time they cover.
    public static func write(
        _ lines: [String], from start: Date, to end: Date, in folder: URL, timeZone: TimeZone = .current
    ) throws -> URL {
        let file = folder.appending(path: "Havus-log-\(fileDate(end, timeZone: timeZone)).txt")
        let header = [
            "Havus's log from \(timestamp(start, timeZone: timeZone)) to \(timestamp(end, timeZone: timeZone)).",
            "Paths and the names of files, apps and agents show as <private> or a hash.",
            "",
        ]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data((header + lines).joined(separator: "\n").appending("\n").utf8).write(to: file, options: .atomic)
        return file
    }

    /// Such as `2026-11-09 06:26:31.123 +0700 notice [scan] developer junk: 8 items, …`.
    static func line(
        date: Date, level: String, category: String, _ message: String, timeZone: TimeZone = .current
    ) -> String {
        "\(timestamp(date, timeZone: timeZone)) \(level) [\(category)] \(message)"
    }

    static func name(of level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "default"
        }
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        format(date, "yyyy-MM-dd HH:mm:ss.SSS Z", timeZone: timeZone)
    }

    private static func fileDate(_ date: Date, timeZone: TimeZone) -> String {
        format(date, "yyyy-MM-dd-HHmmss", timeZone: timeZone)
    }

    /// The same digits whatever the user's language and calendar.
    private static func format(_ date: Date, _ pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
