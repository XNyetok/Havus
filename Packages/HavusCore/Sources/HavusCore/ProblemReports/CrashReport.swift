import Foundation

/// A crash report macOS wrote when an app quit unexpectedly.
///
/// macOS keeps the reports of the user's own apps in `~/Library/Logs/DiagnosticReports`, named after the process,
/// such as `Havus-2026-11-08-201402.ips`, and later moves them into `Retired` there. Apple passes them on only to
/// developers of App Store apps, so Havus offers to help the user send one. It never sends anything itself.
public struct CrashReport: Sendable, Hashable {
    public let url: URL
    /// When the app crashed: the file's modification date, which stays the same when macOS moves the report into
    /// `Retired`.
    public let date: Date

    /// Where macOS keeps the crash reports of the user's apps.
    public static func folders(home: URL) -> [URL] {
        let reports = home.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        return [reports, reports.appending(path: "Retired", directoryHint: .isDirectory)]
    }

    /// The crash reports in `folders` of the app with `bundleIdentifier`, whose process is called `processName`,
    /// newest first. With `since`, only the ones made after it.
    ///
    /// A file counts when its name starts with the process name and ends in `.ips`, and its first line says it's a
    /// crash (`bug_type` 309) of that bundle identifier. Debug builds have an identifier of their own, so they never
    /// pick up the reports of a release, or the other way around.
    public static func find(
        in folders: [URL], processName: String, bundleIdentifier: String, since: Date? = nil
    ) -> [CrashReport] {
        var reports: [CrashReport] = []
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            else { continue }
            for name in names where name.hasPrefix("\(processName)-") && name.hasSuffix(".ips") {
                let url = folder.appending(path: name, directoryHint: .notDirectory)
                guard
                    let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                    since.map({ date > $0 }) ?? true,
                    isCrash(at: url, of: bundleIdentifier)
                else { continue }
                reports.append(CrashReport(url: url, date: date))
            }
        }
        return reports.sorted { $0.date > $1.date }
    }

    /// Writes a copy for the user to look at and attach, named `<report>.ips.txt` because GitHub doesn't take `.ips`
    /// files. macOS writes the user's home folder into paths, such as the one the app runs from; the copy reads `~`
    /// instead.
    public func writeShareableCopy(to folder: URL, home: URL) throws -> URL {
        let text = try String(contentsOf: url, encoding: .utf8)
        let copy = folder.appending(path: url.lastPathComponent + ".txt", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.hidingHome(home, in: text).utf8).write(to: copy, options: .atomic)
        return copy
    }

    static func hidingHome(_ home: URL, in text: String) -> String {
        var path = home.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty else { return text }
        // The report is JSON, where macOS writes `/` as `\/`.
        let escaped = path.replacingOccurrences(of: "/", with: "\\/")
        return text.replacingOccurrences(of: escaped + "\\/", with: "~\\/")
            .replacingOccurrences(of: path + "/", with: "~/")
    }

    /// Whether the report's first line, a JSON header, describes a crash of the app with `bundleIdentifier`.
    private static func isCrash(at url: URL, of bundleIdentifier: String) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        // The header takes a few hundred bytes; the rest of the report can run to hundreds of kilobytes.
        guard let start = try? file.read(upToCount: 4_096),
            let line = start.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
            let header = try? JSONDecoder().decode(Header.self, from: Data(line))
        else { return false }
        return header.bugType == "309" && header.bundleID == bundleIdentifier
    }

    private struct Header: Decodable {
        let bugType: String?
        let bundleID: String?

        enum CodingKeys: String, CodingKey {
            case bugType = "bug_type"
            case bundleID
        }
    }
}
