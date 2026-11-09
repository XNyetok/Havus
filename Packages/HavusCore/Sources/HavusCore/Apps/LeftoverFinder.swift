import Foundation

/// A file or folder an app left behind in `~/Library`.
public struct Leftover: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case applicationSupport, caches, preferences, containers, groupContainers, savedState
        case logs, httpStorage, webKit, cookies, launchAgents, applicationScripts
    }

    public enum Match: Sendable, Hashable {
        /// Named after the app's bundle identifier, alone or with an ending macOS gives an app's files, such as
        /// `.plist`. Also a launch agent whose name only starts with it, when its file points to the app. Reliable,
        /// selected by default.
        case bundleIdentifier
        /// Starts with the app's bundle identifier and a dot, so it may belong to another app whose identifier starts
        /// the same way, such as Google Chrome for Testing (`com.google.chrome.for.testing`) for Google Chrome. The
        /// user should check first.
        case bundleIdentifierPrefix
        /// Named after the app's name. Probably right, but the user should check first.
        case appName
    }

    public let url: URL
    public let kind: Kind
    public let match: Match
    /// Bytes on disk. When ``isFullyReadable`` is `false`, only what Havus could read.
    public let size: Int64
    /// `false` when macOS kept Havus out of some or all of it, so ``size`` may be too low, or zero.
    public let isFullyReadable: Bool

    public var id: URL { url }
}

/// Finds data an app keeps in the user's Library, so it can be removed together with the app.
public struct LeftoverFinder: Sendable {
    struct Location: Sendable {
        let kind: Leftover.Kind
        let relativePath: String
        /// Whether a folder named exactly like the app counts. Only where apps really do that.
        let matchesAppName: Bool
    }

    static let locations: [Location] = [
        Location(kind: .applicationSupport, relativePath: "Library/Application Support", matchesAppName: true),
        Location(kind: .caches, relativePath: "Library/Caches", matchesAppName: true),
        Location(kind: .preferences, relativePath: "Library/Preferences", matchesAppName: false),
        Location(kind: .preferences, relativePath: "Library/Preferences/ByHost", matchesAppName: false),
        Location(kind: .containers, relativePath: "Library/Containers", matchesAppName: false),
        Location(kind: .groupContainers, relativePath: "Library/Group Containers", matchesAppName: false),
        Location(kind: .savedState, relativePath: "Library/Saved Application State", matchesAppName: false),
        Location(kind: .logs, relativePath: "Library/Logs", matchesAppName: true),
        Location(kind: .httpStorage, relativePath: "Library/HTTPStorages", matchesAppName: false),
        Location(kind: .webKit, relativePath: "Library/WebKit", matchesAppName: false),
        Location(kind: .cookies, relativePath: "Library/Cookies", matchesAppName: false),
        Location(kind: .launchAgents, relativePath: "Library/LaunchAgents", matchesAppName: false),
        Location(kind: .applicationScripts, relativePath: "Library/Application Scripts", matchesAppName: false),
    ]

    /// Folder names too generic to ever match an app by name.
    static let genericNames: Set<String> = [
        "apple", "google", "microsoft", "adobe", "mozilla", "jetbrains", "cache", "caches", "logs", "data",
        "helper", "updater",
    ]

    public let home: URL

    public init(home: URL = .homeDirectory) {
        self.home = home
    }

    /// Every folder results can come from. Pass these to ``FileRemover`` as allowed roots.
    public var searchRoots: [URL] {
        Self.locations.map { home.appending(path: $0.relativePath, directoryHint: .isDirectory) }
    }

    /// Blocking.
    /// - Parameters:
    ///   - otherBundleIdentifiers: IDs of the other installed apps, so their data is never claimed.
    ///   - exclusions: Leftovers they block are left out.
    public func leftovers(
        for app: InstalledApp, otherBundleIdentifiers: Set<String> = [],
        excluding exclusions: ExclusionList = ExclusionList()
    ) -> [Leftover] {
        let bundleID = app.bundleIdentifier.lowercased()
        let others = otherBundleIdentifiers.map { $0.lowercased() }.filter { $0.count > bundleID.count }
        let names = Self.nameCandidates(for: app)
        var results: [Leftover] = []
        var seen: Set<[String]> = []

        for location in Self.locations {
            if Task.isCancelled { break }
            let folder = home.appending(path: location.relativePath, directoryHint: .isDirectory)
            guard
                let children = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil, options: [])
            else { continue }

            for child in children {
                let name = child.lastPathComponent.lowercased()
                var match: Leftover.Match
                if let byIdentifier = Self.identifierMatch(name, bundleID: bundleID, kind: location.kind),
                    !others.contains(where: { Self.identifierMatch(name, bundleID: $0, kind: location.kind) != nil })
                {
                    match = byIdentifier
                } else if location.matchesAppName, names.contains(name) {
                    match = .appName
                } else {
                    continue
                }
                guard !exclusions.blocks(child), seen.insert(child.pathComponents).inserted else { continue }
                // A launch agent's file can say which app it belongs to, the way Jalan Otomatis reads it.
                if match == .bundleIdentifierPrefix, location.kind == .launchAgents,
                    LaunchAgentCatalog.isAgent(at: child, of: app)
                {
                    match = .bundleIdentifier
                }
                let measurement = DirectorySize.measure(child)
                results.append(
                    Leftover(
                        url: child, kind: location.kind, match: match,
                        size: measurement.bytes, isFullyReadable: measurement.isComplete))
            }
        }
        return results
    }

    /// Endings macOS adds to a bundle identifier in the names of an app's own files.
    static let fileEndings: Set<Substring> = ["plist", "savedstate", "binarycookies"]

    /// How `name` is named after `bundleID`, or `nil` when it isn't. Both are lowercased.
    static func identifierMatch(_ name: String, bundleID: String, kind: Leftover.Kind) -> Leftover.Match? {
        if name == bundleID { return .bundleIdentifier }
        // Group containers are named "<team ID>.<bundle ID>" or "group.<bundle ID>".
        if kind == .groupContainers, name.hasSuffix("." + bundleID) { return .bundleIdentifier }
        guard name.hasPrefix(bundleID + ".") else { return nil }
        let ending = name.dropFirst(bundleID.count + 1)
        if fileEndings.contains(ending) || isByHostEnding(ending) { return .bundleIdentifier }
        // Any other ending, such as "for.testing.plist", may be the rest of another app's bundle identifier.
        return .bundleIdentifierPrefix
    }

    /// `<host UUID>.plist`, the ending of a ByHost preferences file.
    private static func isByHostEnding(_ ending: Substring) -> Bool {
        ending.hasSuffix(".plist") && UUID(uuidString: String(ending.dropLast(".plist".count))) != nil
    }

    static func nameCandidates(for app: InstalledApp) -> Set<String> {
        // Apple's apps use names (Mail, Music, …) that collide with system folders.
        guard !app.bundleIdentifier.lowercased().hasPrefix("com.apple.") else { return [] }
        let names = [app.name, app.bundleName]
            .compactMap { $0?.lowercased() }
            .filter { $0.count >= 3 && !genericNames.contains($0) }
        return Set(names)
    }
}
