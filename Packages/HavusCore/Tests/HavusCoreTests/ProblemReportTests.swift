import Foundation
import Testing

@testable import HavusCore

struct CrashReportTests {
    private let reports = "Library/Logs/DiagnosticReports"

    /// A report like the ones macOS writes: a JSON header on the first line, then the report itself.
    @discardableResult
    private func makeReport(
        _ home: TemporaryHome, _ relativePath: String, bundleID: String? = "id.nyetok.havus", bugType: String = "309",
        date: Date, body: String = #"{"procPath" : "\/Applications\/Havus.app\/Contents\/MacOS\/Havus"}"#
    ) throws -> URL {
        var header = #"{"app_name":"Havus","app_version":"0.4.0","bug_type":"\#(bugType)""#
        if let bundleID {
            header += #","bundleID":"\#(bundleID)""#
        }
        header += "}"
        let file = home.url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((header + "\n" + body).utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    private func find(_ home: TemporaryHome, since: Date? = nil) -> [String] {
        CrashReport.find(
            in: CrashReport.folders(home: home.url), processName: "Havus", bundleIdentifier: "id.nyetok.havus",
            since: since
        ).map(\.url.lastPathComponent)
    }

    @Test func findsTheAppsCrashesInBothFoldersNewestFirst() throws {
        let home = try TemporaryHome()
        // macOS moves a report into Retired a few hours after the crash.
        try makeReport(home, "\(reports)/Retired/Havus-2026-11-07-101010.ips", date: Date(timeIntervalSince1970: 1_000))
        try makeReport(home, "\(reports)/Havus-2026-11-08-201402.ips", date: Date(timeIntervalSince1970: 2_000))

        #expect(find(home) == ["Havus-2026-11-08-201402.ips", "Havus-2026-11-07-101010.ips"])
    }

    @Test func skipsOtherAppsOtherBuildsAndOtherReports() throws {
        let home = try TemporaryHome()
        let date = Date(timeIntervalSince1970: 1_000)
        try makeReport(home, "\(reports)/Havus-2026-11-08-000001.ips", bundleID: "id.nyetok.havus.debug", date: date)
        try makeReport(home, "\(reports)/Havus-2026-11-08-000002.ips", bundleID: nil, date: date)
        // A hang, not a crash.
        try makeReport(home, "\(reports)/Havus-2026-11-08-000003.ips", bugType: "298", date: date)
        try makeReport(home, "\(reports)/Safari-2026-11-08-000004.ips", date: date)
        try makeReport(home, "\(reports)/Havus Helper-2026-11-08-000005.ips", date: date)
        try makeReport(home, "\(reports)/Havus-2026-11-08-000006.diag", date: date)
        try home.makeFile("\(reports)/Havus-2026-11-08-000007.ips", bytes: 100)

        #expect(find(home).isEmpty)
    }

    @Test func skipsReportsUpToTheLastOneOffered() throws {
        let home = try TemporaryHome()
        try makeReport(home, "\(reports)/Havus-2026-11-08-000001.ips", date: Date(timeIntervalSince1970: 1_000))
        try makeReport(home, "\(reports)/Havus-2026-11-08-000002.ips", date: Date(timeIntervalSince1970: 2_000))

        #expect(find(home, since: Date(timeIntervalSince1970: 1_000)) == ["Havus-2026-11-08-000002.ips"])
        #expect(find(home, since: Date(timeIntervalSince1970: 2_000)).isEmpty)
    }

    @Test func findsNothingWhenMacOSHasNoReportsYet() throws {
        let home = try TemporaryHome()

        #expect(find(home).isEmpty)
    }

    @Test func hidesTheHomeFolderInPaths() {
        let home = URL(filePath: "/Users/kurnia/", directoryHint: .isDirectory)
        let report =
            #"{"procPath" : "\/Users\/kurnia\/Downloads\/Havus.app", "a" : "\/Users\/kurniawan\/x", "b" : "/Users/kurnia/y"}"#

        // A folder whose name only starts the same, like another user's, stays as it is.
        #expect(
            CrashReport.hidingHome(home, in: report)
                == #"{"procPath" : "~\/Downloads\/Havus.app", "a" : "\/Users\/kurniawan\/x", "b" : "~/y"}"#)
    }

    @Test func writesACopyToShareAsText() throws {
        let home = try TemporaryHome()
        var path = home.url.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        let escapedPath = path.replacingOccurrences(of: "/", with: "\\/")
        let file = try makeReport(
            home, "\(reports)/Havus-2026-11-08-201402.ips", date: .now,
            body: #"{"procPath" : "\#(escapedPath)\/Applications\/Havus.app\/Contents\/MacOS\/Havus"}"#)
        let report = CrashReport(url: file, date: .now)

        let copy = try report.writeShareableCopy(to: home.url.appending(path: "Shared"), home: home.url)
        let text = try String(contentsOf: copy, encoding: .utf8)

        #expect(copy.lastPathComponent == "Havus-2026-11-08-201402.ips.txt")
        #expect(text.hasPrefix(#"{"app_name":"Havus""#))
        #expect(text.contains(#""procPath" : "~\/Applications\/Havus.app\/Contents\/MacOS\/Havus""#))
        #expect(!text.contains(escapedPath))
        // The report itself stays as macOS wrote it.
        #expect(try String(contentsOf: file, encoding: .utf8).contains(escapedPath))
    }
}

struct ProblemReportTests {
    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func opensTheBugReportFormWithWhatHavusKnows() throws {
        let url = try #require(
            ProblemReport.issueURL(
                title: "Havus quit unexpectedly", version: "0.4.0 (12)", macOS: "macOS 27.2 (26B123)",
                whatHappened: "It quit. 1+1 & a=b"))

        #expect(url.absoluteString.hasPrefix("https://github.com/XNyetok/Havus/issues/new?template=bug_report.yml&"))
        #expect(
            queryItems(url) == [
                "template": "bug_report.yml", "title": "Havus quit unexpectedly", "version": "0.4.0 (12)",
                "macos": "macOS 27.2 (26B123)", "what-happened": "It quit. 1+1 & a=b",
            ])
        // GitHub would read a + as a space.
        #expect(!url.absoluteString.contains("+"))
    }

    @Test func leavesOutWhatHavusDoesntKnow() throws {
        let url = try #require(ProblemReport.issueURL(title: nil, version: nil, macOS: "macOS 27.2", whatHappened: nil))

        #expect(queryItems(url) == ["template": "bug_report.yml", "macos": "macOS 27.2"])
    }

    @Test func writesAnEmailToTheMaintainer() throws {
        let url = try #require(
            ProblemReport.emailURL(subject: "Havus quit unexpectedly", body: "What happened?\n\n1+1 & a=b"))

        #expect(url.absoluteString.hasPrefix("mailto:debi@elysiumx.org?"))
        #expect(queryItems(url) == ["subject": "Havus quit unexpectedly", "body": "What happened?\n\n1+1 & a=b"])
        #expect(!url.absoluteString.contains("+"))
    }
}

struct MacInfoTests {
    @Test func namesTheMacOSVersionWithItsBuild() {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        #expect(MacInfo.osVersion.hasPrefix("macOS \(version.majorVersion).\(version.minorVersion)"))
        #expect(MacInfo.osVersion.hasSuffix(")"))
    }

    @Test func knowsAppleSilicon() {
        // Under Rosetta, an Intel build runs on Apple silicon too, so only the native case is certain.
        #if arch(arm64)
            #expect(MacInfo.isAppleSilicon)
        #endif
    }
}
