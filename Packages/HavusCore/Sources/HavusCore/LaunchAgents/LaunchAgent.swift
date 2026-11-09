import Darwin
import Foundation

/// A property list in `~/Library/LaunchAgents`: a job that launchd starts for this user alone.
public struct LaunchAgent: Sendable, Hashable, Identifiable {
    /// What the file asks launchd to run.
    public struct Job: Sendable, Hashable {
        /// launchd's name for the job. `launchctl` commands use it, and it outlives the file.
        public let label: String
        /// The program launchd runs, when the file names it by its full path.
        public let program: URL?
        /// `true` only when ``program`` surely doesn't exist, so launchd can't start the job.
        public let isProgramMissing: Bool
        public let schedule: Schedule
        /// The file's `Disabled` key. launchd skips the job unless it was turned on with `launchctl enable`.
        public let isDisabledInFile: Bool
    }

    /// When launchd starts the job. When the file asks for more than one, the case that runs it most often.
    public enum Schedule: Sendable, Hashable {
        /// `KeepAlive`: starts at login and starts again whenever it quits.
        case alwaysRunning
        /// `RunAtLoad`: starts at every login.
        case atLogin
        /// `StartInterval`: every so many seconds.
        case interval(seconds: Int)
        /// `StartCalendarInterval`: at set times, such as every day at 9:00.
        case calendar
        /// Only when something asks for it, such as another program or a change in a watched folder.
        case onDemand
    }

    /// The app a job belongs to, when Havus can tell.
    public struct Owner: Sendable, Hashable {
        /// The app bundle.
        public let url: URL
        /// Name as shown in Finder.
        public let name: String
        /// Set when **Hapus Aplikasi** lists the app, so the user can remove it there.
        public let installedApp: InstalledApp?
    }

    /// The property list file.
    public let url: URL
    /// `nil` when launchd can't load the file, for example an empty or broken one, so it never runs.
    public let job: Job?
    public let owner: Owner?

    public var id: URL { url }

    /// The owner's name, or else launchd's name for the job, or else the file name.
    public var name: String {
        owner?.name ?? job?.label ?? url.deletingPathExtension().lastPathComponent
    }
}

/// Lists the launch agents in `~/Library/LaunchAgents`, the only ones Havus may change without root.
public struct LaunchAgentCatalog: Sendable {
    public let home: URL

    public init(home: URL = .homeDirectory) {
        self.home = home
    }

    /// Where the agents live. Pass it to ``FileRemover`` as the allowed root.
    public var folder: URL {
        home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    /// Blocking. Sorted by name. Only property lists directly in ``folder`` count: launchd ignores subfolders, where
    /// some people keep the agents they turned off.
    /// - Parameters:
    ///   - installedApps: The apps ``AppCatalog`` lists, to tell which app each agent belongs to.
    ///   - exclusions: Agents whose file they block are left out.
    public func agents(installedApps: [InstalledApp] = [], excluding exclusions: ExclusionList = ExclusionList())
        -> [LaunchAgent]
    {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        let apps = AppIndex(installedApps)
        return
            children
            .filter { url in
                url.pathExtension.lowercased() == "plist"
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
                    && !exclusions.blocks(url)
            }
            .map { Self.agent(at: $0, apps: apps) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame
                    ? lhs.url.lastPathComponent < rhs.url.lastPathComponent : order == .orderedAscending
            }
    }

    static func agent(at url: URL, apps: AppIndex) -> LaunchAgent {
        guard
            let data = try? Data(contentsOf: url),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let job = job(from: info)
        else { return LaunchAgent(url: url, job: nil, owner: nil) }
        return LaunchAgent(url: url, job: job, owner: owner(of: job, info: info, apps: apps))
    }

    /// `nil` when launchd would refuse the file: it needs a label and something to run (launchd.plist(5)).
    static func job(from info: [String: Any]) -> LaunchAgent.Job? {
        guard let label = info["Label"] as? String, !label.isEmpty else { return nil }
        let arguments = info["ProgramArguments"] as? [String] ?? []
        let path = info["Program"] as? String ?? arguments.first
        // BundleProgram is relative to an app bundle that only macOS knows, so Havus can't check it.
        guard path?.isEmpty == false || info["BundleProgram"] is String else { return nil }

        // launchd doesn't expand `~` or look up commands without a path here, so only a full path is checked.
        let program = path.flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
        return LaunchAgent.Job(
            label: label,
            program: program,
            isProgramMissing: program.map(isMissing) ?? false,
            schedule: schedule(from: info),
            isDisabledInFile: info["Disabled"] as? Bool ?? false
        )
    }

    static func schedule(from info: [String: Any]) -> LaunchAgent.Schedule {
        if info["KeepAlive"] as? Bool == true { return .alwaysRunning }
        if info["RunAtLoad"] as? Bool == true { return .atLogin }
        // A KeepAlive dictionary with SuccessfulExit implies RunAtLoad (launchd.plist(5)).
        if let keepAlive = info["KeepAlive"] as? [String: Any], keepAlive["SuccessfulExit"] != nil { return .atLogin }
        if let seconds = info["StartInterval"] as? Int, seconds > 0 { return .interval(seconds: seconds) }
        if info["StartCalendarInterval"] != nil { return .calendar }
        return .onDemand
    }

    /// `true` only when the program surely isn't there. A program macOS hides from Havus, or one on a disk that isn't
    /// connected right now, doesn't count.
    static func isMissing(_ program: URL) -> Bool {
        let path = program.path(percentEncoded: false)
        guard !path.hasPrefix("/Volumes/") else { return false }
        var info = stat()
        guard stat(path, &info) != 0 else { return false }
        return errno == ENOENT || errno == ENOTDIR
    }

    /// Tries what macOS itself shows in Login Items first, then the app that holds the program, then the label.
    static func owner(of job: LaunchAgent.Job, info: [String: Any], apps: AppIndex) -> LaunchAgent.Owner? {
        namedOwner(of: job, info: info, apps: apps) ?? apps.app(labelling: job.label).map(LaunchAgent.Owner.init)
    }

    /// The owner the file itself points to: the app in `AssociatedBundleIdentifiers`, or the app that holds the program.
    /// Unlike the label, neither can be another app's whose bundle identifier only starts the same way.
    static func namedOwner(of job: LaunchAgent.Job, info: [String: Any], apps: AppIndex) -> LaunchAgent.Owner? {
        let associated = info["AssociatedBundleIdentifiers"]
        let bundleIDs = associated as? [String] ?? (associated as? String).map { [$0] } ?? []
        if let app = bundleIDs.lazy.compactMap(apps.app(withBundleIdentifier:)).first {
            return LaunchAgent.Owner(app)
        }

        if let bundle = job.program.flatMap(outermostApp) {
            if let app = apps.app(at: bundle) { return LaunchAgent.Owner(app) }
            if !job.isProgramMissing {
                return LaunchAgent.Owner(
                    url: bundle, name: bundle.deletingPathExtension().lastPathComponent, installedApp: nil)
            }
        }
        return nil
    }

    /// Whether the agent file at `url` points to `app` as its owner, through ``namedOwner(of:info:apps:)``.
    static func isAgent(at url: URL, of app: InstalledApp) -> Bool {
        guard
            let data = try? Data(contentsOf: url),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let job = job(from: info)
        else { return false }
        return namedOwner(of: job, info: info, apps: AppIndex([app]))?.installedApp == app
    }

    /// `/Applications/Example.app/Contents/Library/Helper.app/Contents/MacOS/Helper` → `/Applications/Example.app`
    static func outermostApp(containing program: URL) -> URL? {
        let components = program.standardizedFileURL.pathComponents
        guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }), index > 0 else {
            return nil
        }
        return URL(filePath: "/" + components[1...index].joined(separator: "/"), directoryHint: .isDirectory)
    }
}

extension LaunchAgent.Owner {
    init(_ app: InstalledApp) {
        self.init(url: app.url, name: app.name, installedApp: app)
    }
}

/// Installed apps by bundle identifier and by location.
struct AppIndex {
    private let byBundleID: [String: InstalledApp]
    private let byPath: [[String]: InstalledApp]

    init(_ apps: [InstalledApp]) {
        byBundleID = Dictionary(
            apps.map { ($0.bundleIdentifier.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        byPath = Dictionary(
            apps.map { ($0.url.standardizedFileURL.pathComponents, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func app(withBundleIdentifier bundleID: String) -> InstalledApp? {
        byBundleID[bundleID.lowercased()]
    }

    func app(at url: URL) -> InstalledApp? {
        byPath[url.standardizedFileURL.pathComponents]
    }

    /// The app with the longest bundle identifier that starts the label, such as `com.example.app` for
    /// `com.example.app.helper`.
    func app(labelling label: String) -> InstalledApp? {
        let parts = label.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }
        for count in stride(from: parts.count, through: 2, by: -1) {
            if let app = byBundleID[parts.prefix(count).joined(separator: ".")] { return app }
        }
        return nil
    }
}
