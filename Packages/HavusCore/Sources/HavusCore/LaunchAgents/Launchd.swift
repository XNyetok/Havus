import Darwin
import Foundation
import ServiceManagement
import os

/// What launchd and Login Items say about the user's launch agents at one moment.
public struct LaunchdSnapshot: Sendable, Hashable {
    /// Labels of the jobs launchd has loaded in the user's session.
    public var loaded: Set<String> = []
    /// Labels of the loaded jobs that are running right now.
    public var running: Set<String> = []
    /// Labels turned off (`true`) or on (`false`) with `launchctl disable` or `enable`, which outrank the file's
    /// `Disabled` key. launchd keeps them by label, so they also cover a file that an app writes again.
    public var overrides: [String: Bool] = [:]
    /// Files of the agents the user switched off in System Settings → General → Login Items & Extensions.
    public var offInSystemSettings: Set<URL> = []

    public init() {}
}

extension LaunchAgent {
    public enum Status: Sendable, Hashable {
        /// launchd starts it as its schedule says.
        case on
        /// Turned off with `launchctl disable`, as Havus does, or by the file's `Disabled` key.
        case off
        /// Switched off in System Settings → General → Login Items & Extensions, which only the user can change.
        case offInSystemSettings
        /// launchd can't load the file, so it never runs.
        case invalid
    }

    public func status(in snapshot: LaunchdSnapshot) -> Status {
        guard let job else { return .invalid }
        if snapshot.offInSystemSettings.contains(url) { return .offInSystemSettings }
        let isDisabled = snapshot.overrides[job.label] ?? job.isDisabledInFile
        return isDisabled ? .off : .on
    }

    /// Also `true` for an agent that was turned off but keeps running until the user logs out.
    public func isRunning(in snapshot: LaunchdSnapshot) -> Bool {
        job.map { snapshot.running.contains($0.label) } ?? false
    }
}

/// Reads and changes the user's launch agents with `/bin/launchctl`, in their own GUI domain (`gui/<uid>`), which
/// needs no root.
///
/// Turning an agent off or on changes only launchd's record of it, never the file, and can always be undone.
/// Removing one moves its file to the Trash through ``FileRemover``.
public struct Launchd: Sendable {
    public struct CommandResult: Sendable, Hashable {
        public let status: Int32
        public let output: String
        public let error: String

        public init(status: Int32, output: String = "", error: String = "") {
            self.status = status
            self.output = output
            self.error = error
        }
    }

    /// A `launchctl` command that failed, with what it said, such as "Operation not permitted".
    public struct Failure: Error, Sendable, Hashable {
        public let message: String
    }

    /// Runs `launchctl` with the given arguments. Injectable, so tests never change the real launchd.
    public typealias Command = @Sendable (_ arguments: [String]) -> CommandResult
    /// Whether the user switched an agent off in Login Items. Injectable, so tests don't depend on this Mac.
    public typealias LoginItemsCheck = @Sendable (_ file: URL) -> Bool

    /// `gui/<uid>`: the user's login session, where their launch agents run.
    let domain: String
    private let run: Command
    private let isOffInSystemSettings: LoginItemsCheck

    public init(
        uid: uid_t = getuid(), run: @escaping Command = Launchd.launchctl,
        isOffInSystemSettings: @escaping LoginItemsCheck = Launchd.isOffInLoginItems
    ) {
        domain = "gui/\(uid)"
        self.run = run
        self.isOffInSystemSettings = isOffInSystemSettings
    }

    /// Blocking. What launchd and Login Items say about `agents` now.
    public func snapshot(of agents: [LaunchAgent]) -> LaunchdSnapshot {
        var snapshot = LaunchdSnapshot()
        (snapshot.loaded, snapshot.running) = Self.jobs(fromList: run(["list"]).output)
        snapshot.overrides = Self.overrides(fromPrintDisabled: run(["print-disabled", domain]).output)
        snapshot.offInSystemSettings = Set(agents.filter { $0.job != nil }.map(\.url).filter(isOffInSystemSettings))
        return snapshot
    }

    /// Blocking. Keeps launchd from starting the job again, also after a restart, and stops it if it's running.
    /// The file stays as it is, so the app that wrote it has no reason to write it again.
    public func turnOff(_ agent: LaunchAgent) throws(Failure) {
        guard let job = agent.job else { return }
        try check(run(["disable", target(job.label)]), of: "disable")
        // Fails when the job isn't loaded, and then there's nothing to stop.
        stop(job.label)
        Log.launchd.notice("Turned off \(job.label, privacy: .private(mask: .hash))")
    }

    /// Blocking. Lets launchd start the job again, and loads it now like at login.
    public func turnOn(_ agent: LaunchAgent) throws(Failure) {
        guard let job = agent.job else { return }
        try check(run(["enable", target(job.label)]), of: "enable")
        // Fails when the job is loaded already, or when launchd won't load it in this session. Either way, it's on and
        // starts at the next login.
        _ = run(["bootstrap", domain, agent.url.path(percentEncoded: false)])
        Log.launchd.notice("Turned on \(job.label, privacy: .private(mask: .hash))")
    }

    /// Blocking. Moves the agent's file to the Trash with `remover`, then stops the job if it's running. Nothing is
    /// stopped when the file stays. Restoring the file from the Trash brings the job back at the next login.
    public func remove(_ agent: LaunchAgent, with remover: FileRemover, allowedRoot: URL) -> FileRemover.Report {
        let report = remover.remove([agent.url], method: .moveToTrash, allowedRoots: [allowedRoot])
        if report.removed.contains(agent.url) {
            Log.launchd.notice(
                "Moved \(agent.url.lastPathComponent, privacy: .private(mask: .hash)) to the Trash")
            if let label = agent.job?.label {
                stop(label)
            }
        }
        return report
    }

    private func stop(_ label: String) {
        _ = run(["bootout", target(label)])
    }

    private func target(_ label: String) -> String {
        "\(domain)/\(label)"
    }

    /// What launchctl says can name the job, so the log keeps it private.
    private func check(_ result: CommandResult, of command: String) throws(Failure) {
        guard result.status != 0 else { return }
        let said = [result.error, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let message = said ?? "launchctl exited with status \(result.status)"
        Log.launchd.error(
            "launchctl \(command, privacy: .public) failed with status \(result.status): \(message, privacy: .private)")
        throw Failure(message: message)
    }

    // MARK: - Reading launchctl

    /// Reads `launchctl list`: a header, then one job per line with its process ID, last exit status and label,
    /// separated by tabs. The process ID is `-` when the job isn't running.
    static func jobs(fromList output: String) -> (loaded: Set<String>, running: Set<String>) {
        var loaded: Set<String> = []
        var running: Set<String> = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, fields[0] != "PID", !fields[2].isEmpty else { continue }
            let label = String(fields[2])
            loaded.insert(label)
            if Int32(fields[0]) != nil { running.insert(label) }
        }
        return (loaded, running)
    }

    /// Reads the `disabled services = { … }` block of `launchctl print-disabled`, with lines such as
    /// `"com.example.agent" => disabled`. Older macOS versions wrote `true` and `false` instead.
    static func overrides(fromPrintDisabled output: String) -> [String: Bool] {
        var overrides: [String: Bool] = [:]
        var isInBlock = false
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("= {") {
                isInBlock = line.hasPrefix("disabled services")
                continue
            }
            if line == "}" {
                isInBlock = false
                continue
            }
            guard isInBlock, line.hasPrefix("\""), let arrow = line.range(of: "\" => ", options: .backwards) else {
                continue
            }
            let label = String(line[line.index(after: line.startIndex)..<arrow.lowerBound])
            switch line[arrow.upperBound...] {
            case "disabled", "true": overrides[label] = true
            case "enabled", "false": overrides[label] = false
            default: continue
            }
        }
        return overrides
    }

    // MARK: - The real thing

    public static let launchctl: Command = { arguments in
        execute(URL(filePath: "/bin/launchctl"), arguments)
    }

    /// Asks Background Task Management, which keeps the switches in Login Items. Havus can read them, but only the
    /// user can flip them.
    public static let isOffInLoginItems: LoginItemsCheck = { file in
        SMAppService.statusForLegacyPlist(at: file) == .requiresApproval
    }

    static func execute(_ executable: URL, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, error: error.localizedDescription)
        }

        // Read both pipes at the same time, so neither can fill up and leave the command waiting forever.
        let errorText = CollectedText()
        let reader = errors.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorText.set(reader.readDataToEndOfFile())
            group.leave()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            error: errorText.value
        )
    }
}

/// Text that one thread reads from a pipe while another waits for it.
private final class CollectedText: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }

    func set(_ newData: Data) {
        lock.lock()
        data = newData
        lock.unlock()
    }
}
