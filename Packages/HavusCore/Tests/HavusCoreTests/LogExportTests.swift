import Foundation
import Testing
import os

@testable import HavusCore

struct LogExportTests {
    private let jakarta = TimeZone(secondsFromGMT: 7 * 60 * 60)!
    /// 2026-11-09 06:26:31.123 in Jakarta.
    private let date = Date(timeIntervalSince1970: 1_794_180_391.123)

    @Test func writesOneLinePerEntry() {
        let line = LogExport.line(
            date: date, level: "notice", category: "scan", "developer junk: 8 items", timeZone: jakarta)

        #expect(line == "2026-11-09 06:26:31.123 +0700 notice [scan] developer junk: 8 items")
    }

    @Test func writesAFileThatSaysWhichTimeItCovers() throws {
        let home = try TemporaryHome()
        let start = date.addingTimeInterval(-3 * 60 * 60)

        let file = try LogExport.write(
            ["first line", "second line"], from: start, to: date, in: home.url.appending(path: "Shared"),
            timeZone: jakarta)

        #expect(file.lastPathComponent == "Havus-log-2026-11-09-062631.txt")
        #expect(
            try String(contentsOf: file, encoding: .utf8) == """
                Havus's log from 2026-11-09 03:26:31.123 +0700 to 2026-11-09 06:26:31.123 +0700.
                Paths and the names of files, apps and agents show as <private> or a hash.

                first line
                second line

                """)
    }

    @Test func readsBackWhatThisProcessLogged() async throws {
        let marker = UUID().uuidString
        let start = Date.now.addingTimeInterval(-60)
        Log.reports.notice("Export test \(marker, privacy: .public)")

        // The log takes a moment to show what was just written.
        var lines: [String] = []
        for _ in 0..<20 {
            lines = LogExport.lines(
                of: ProcessInfo.processInfo.processName, from: start, to: .now.addingTimeInterval(60))
            if lines.contains(where: { $0.hasSuffix("notice [reports] Export test \(marker)") }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(lines.contains { $0.hasSuffix("notice [reports] Export test \(marker)") })
    }
}
