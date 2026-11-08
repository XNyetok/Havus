import CoreServices
import Foundation
import os

public struct LargeFile: Sendable, Hashable, Identifiable {
    public let url: URL
    /// Bytes stored on this Mac. Cloud-only placeholders count as (almost) zero and are skipped.
    public let size: Int64
    public let lastOpened: Date?
    public let modified: Date?

    public var id: URL { url }
}

/// Finds big files in the user's folders, using the Spotlight index when it can.
public struct LargeFileFinder: Sendable {
    public struct Criteria: Sendable, Hashable {
        public var minimumSize: Int64
        /// Keep only files not opened since this date (or, if never opened, not modified since).
        public var notOpenedSince: Date?

        public init(minimumSize: Int64, notOpenedSince: Date? = nil) {
            self.minimumSize = minimumSize
            self.notOpenedSince = notOpenedSince
        }
    }

    struct Candidate {
        let url: URL
        let lastOpened: Date?
    }

    /// Scanned directly when Spotlight returns nothing (e.g. indexing is off).
    static let fallbackFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]

    public let home: URL
    /// Libraries left out without being looked at, so macOS doesn't ask for permission. `nil` searches everything.
    public let skipped: MediaLibraries?
    private let usesSpotlight: Bool

    public init(home: URL = .homeDirectory, usesSpotlight: Bool = true, skipping skipped: MediaLibraries? = nil) {
        self.home = home
        self.usesSpotlight = usesSpotlight
        self.skipped = skipped
    }

    /// Blocking. Sorted from largest to smallest. Files that `exclusions` blocks are left out.
    public func find(_ criteria: Criteria, excluding exclusions: ExclusionList = ExclusionList()) -> [LargeFile] {
        var candidates = usesSpotlight ? spotlightCandidates(minimumSize: criteria.minimumSize) : []
        if candidates.isEmpty {
            if usesSpotlight {
                Log.scan.notice("Spotlight found no large files, so the usual folders are scanned instead")
            }
            candidates = fileSystemCandidates(minimumSize: criteria.minimumSize)
        }

        let homeComponents = PathGuard.resolved(home).pathComponents
        var packageCache: [[String]: Bool] = [:]
        var files: [LargeFile] = []
        for candidate in candidates {
            if Task.isCancelled { break }
            // Before anything looks at the file: even reading its size would make macOS ask.
            if let skipped, skipped.contain(candidate.url) { continue }
            if let file = refine(candidate, criteria, homeComponents: homeComponents, packageCache: &packageCache),
                !exclusions.blocks(file.url)
            {
                files.append(file)
            }
        }
        return files.sorted { $0.size > $1.size }
    }

    private func refine(
        _ candidate: Candidate, _ criteria: Criteria, homeComponents: [String], packageCache: inout [[String]: Bool]
    ) -> LargeFile? {
        let url = PathGuard.resolved(candidate.url)
        guard Self.isEligible(url.pathComponents, homeComponents: homeComponents),
            !Self.isInsidePackage(url, homeComponents: homeComponents, cache: &packageCache),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
            ]),
            values.isRegularFile == true
        else { return nil }

        let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        guard size >= criteria.minimumSize else { return nil }
        if let cutoff = criteria.notOpenedSince {
            guard let reference = candidate.lastOpened ?? values.contentModificationDate, reference < cutoff else {
                return nil
            }
        }
        return LargeFile(
            url: url, size: size, lastOpened: candidate.lastOpened, modified: values.contentModificationDate)
    }

    /// Inside the home folder, outside `~/Library` (other features own it), and not hidden.
    static func isEligible(_ components: [String], homeComponents: [String]) -> Bool {
        guard PathGuard.isStrictlyInside(components, homeComponents) else { return false }
        let relative = components.dropFirst(homeComponents.count)
        guard relative.first != "Library" else { return false }
        return !relative.contains { $0.hasPrefix(".") }
    }

    /// Files inside packages (Photos libraries, app bundles, …) must never be removed on their own.
    static func isInsidePackage(_ url: URL, homeComponents: [String], cache: inout [[String]: Bool]) -> Bool {
        var folder = url.deletingLastPathComponent()
        while folder.pathComponents.count > homeComponents.count {
            let key = folder.pathComponents
            let isPackage: Bool
            if let cached = cache[key] {
                isPackage = cached
            } else {
                isPackage = (try? folder.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                cache[key] = isPackage
            }
            if isPackage { return true }
            folder.deleteLastPathComponent()
        }
        return false
    }

    private func spotlightCandidates(minimumSize: Int64) -> [Candidate] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, "kMDItemFSSize >= \(minimumSize)" as CFString, nil, nil)
        else { return [] }
        MDQuerySetSearchScope(query, [home.path(percentEncoded: false)] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        defer { MDQueryStop(query) }

        let count = MDQueryGetResultCount(query)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            candidates.append(Candidate(url: URL(filePath: path), lastOpened: lastUsed))
        }
        return candidates
    }

    private func fileSystemCandidates(minimumSize: Int64) -> [Candidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var candidates: [Candidate] = []
        for folderName in Self.fallbackFolders {
            let folder = home.appending(path: folderName, directoryHint: .isDirectory)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: folder, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return candidates }
                if let skipped, skipped.contain(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                    Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) >= minimumSize
                else { continue }
                candidates.append(Candidate(url: url, lastOpened: nil))
            }
        }
        return candidates
    }
}
