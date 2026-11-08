import AppKit
import HavusCore
import Observation
import os

/// Helps the user report a problem: offers a new crash report once, at launch, and answers "Laporkan Masalah…".
///
/// Havus never sends anything itself. It opens a new GitHub issue or an email with the versions filled in, and shows a
/// copy of the crash report and its own recent log lines in Finder, for the user to look at and attach (see
/// docs/architecture.md).
@MainActor
@Observable
final class ProblemReportCenter {
    enum Prompt: Equatable {
        /// Havus crashed since it last offered a report.
        case crash(CrashReport)
        /// The user chose "Laporkan Masalah…". The newest crash report of the past week goes along, if there is one.
        case problem(recentCrash: CrashReport?)

        var crashReport: CrashReport? {
            switch self {
            case .crash(let report): report
            case .problem(let report): report
            }
        }
    }

    enum Channel {
        case gitHub, email
    }

    /// The question on screen, in an alert.
    var prompt: Prompt?

    private let defaults: UserDefaults
    private let home = FileManager.default.homeDirectoryForCurrentUser
    /// Where the files to attach go: Havus's temporary folder, which macOS empties by itself.
    private let shareFolder = FileManager.default.temporaryDirectory.appending(
        path: "Havus", directoryHint: .isDirectory)
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "id.nyetok.havus"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The first launch only notes the time, so reports from versions before this one, which have no debug
        // symbols to read them with, aren't offered.
        if defaults.object(forKey: Key.lastOffered) == nil {
            defaults.set(Date.now, forKey: Key.lastOffered)
        }
    }

    /// At launch: offers the newest crash report since the last one offered, and only once.
    func offerNewCrashReport() {
        let since = defaults.object(forKey: Key.lastOffered) as? Date
        Task {
            guard let newest = await crashReports(since: since).first else { return }
            Log.reports.notice("Offered crash report \(newest.url.lastPathComponent, privacy: .public)")
            defaults.set(newest.date, forKey: Key.lastOffered)
            prompt = .crash(newest)
        }
    }

    /// "Laporkan Masalah…" in the Help menu.
    func reportProblem() {
        Task {
            let recent = await crashReports(since: .now.addingTimeInterval(-7 * 24 * 60 * 60)).first
            prompt = .problem(recentCrash: recent)
        }
    }

    func send(_ prompt: Prompt, via channel: Channel) {
        Log.reports.notice(
            "Opened a problem report \(channel == .gitHub ? "on GitHub" : "by email", privacy: .public), crash report attached: \(prompt.crashReport != nil ? "yes" : "no", privacy: .public)"
        )
        if let url = url(for: prompt, via: channel) {
            NSWorkspace.shared.open(url)
        }
        // Reading the log can take a few seconds, so Finder shows the files once they're written.
        Task {
            var files: [URL] = []
            if let report = prompt.crashReport, let copy = await shareableCopy(of: report) {
                files.append(copy)
            }
            if let log = await logCopy(for: prompt) {
                files.append(log)
            }
            if !files.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(files)
            }
        }
    }

    private func crashReports(since: Date?) async -> [CrashReport] {
        let folders = CrashReport.folders(home: home)
        let bundleIdentifier = bundleIdentifier
        // macOS names a crash report after the process: the executable's name, the same in Debug builds.
        let processName = ProcessInfo.processInfo.processName
        return await Background.run {
            CrashReport.find(in: folders, processName: processName, bundleIdentifier: bundleIdentifier, since: since)
        }
    }

    private func shareableCopy(of report: CrashReport) async -> URL? {
        let folder = shareFolder
        let home = home
        return await Background.run { try? report.writeShareableCopy(to: folder, home: home) }
    }

    /// For a crash, Havus's log lines from the three hours before it. Otherwise, from the past day.
    private func logCopy(for prompt: Prompt) async -> URL? {
        let (start, end): (Date, Date) =
            if case .crash(let report) = prompt {
                (report.date.addingTimeInterval(-3 * 60 * 60), report.date.addingTimeInterval(60))
            } else {
                (.now.addingTimeInterval(-24 * 60 * 60), .now)
            }
        let folder = shareFolder
        let process = ProcessInfo.processInfo.processName
        return await Background.run {
            let lines = LogExport.lines(of: process, from: start, to: end)
            guard !lines.isEmpty else { return nil }
            return try? LogExport.write(lines, from: start, to: end, in: folder)
        }
    }

    private func url(for prompt: Prompt, via channel: Channel) -> URL? {
        let isCrash = if case .crash = prompt { true } else { false }
        switch channel {
        case .gitHub:
            return ProblemReport.issueURL(
                title: isCrash ? String(localized: "Havus berhenti mendadak") : nil,
                version: Bundle.main.versionAndBuild,
                macOS: MacInfo.osVersion,
                whatHappened: isCrash ? String(localized: "Havus berhenti mendadak. Ini laporan crash-nya:") : nil)
        case .email:
            let lines = [
                String(localized: "Apa yang terjadi?"), "", "",
                String(localized: "(Lampirin file yang Havus tunjukin di Finder.)"), "", "—", macDetails,
            ]
            return ProblemReport.emailURL(
                subject: isCrash ? String(localized: "Havus berhenti mendadak") : String(localized: "Masalah di Havus"),
                body: lines.joined(separator: "\n"))
        }
    }

    /// What the bug report form asks for, on one line of the email.
    private var macDetails: String {
        [
            Bundle.main.versionAndBuild.map { "Havus \($0)" },
            MacInfo.osVersion,
            MacInfo.isAppleSilicon ? "Apple silicon" : "Intel",
            FullDiskAccess.isGranted()
                ? String(localized: "Akses Disk Penuh nyala") : String(localized: "Akses Disk Penuh mati"),
        ].compactMap(\.self).joined(separator: " · ")
    }

    private enum Key {
        static let lastOffered = "ProblemReports.lastOfferedCrash"
    }
}
