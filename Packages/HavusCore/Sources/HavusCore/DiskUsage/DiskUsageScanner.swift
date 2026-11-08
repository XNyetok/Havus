import Darwin
import Foundation

/// Something on the disk map: a folder, a package such as an app or a Photos library, or a file.
public struct DiskUsageItem: Sendable, Identifiable {
    public enum Kind: Sendable {
        case folder
        /// A folder Finder shows as one file, such as an app or a Photos library. Measured as a whole, never opened.
        case package
        /// A file, or a symbolic link (never followed).
        case file
    }

    /// The part of a folder's contents that isn't listed item by item.
    public struct OtherItems: Sendable, Hashable {
        public let count: Int
        public let bytes: Int64

        public static let none = OtherItems(count: 0, bytes: 0)
    }

    public let url: URL
    public let kind: Kind
    /// Bytes allocated on disk; for a folder or package, everything inside it.
    public let bytes: Int64
    /// `false` when macOS refused to show some of it, for example another app's data without Full Disk Access.
    /// ``bytes`` then counts only what Havus could read, so it may be too low, or zero.
    public let isComplete: Bool
    /// For a folder: what's inside, largest first. `nil` when the scan didn't keep that list because the folder is
    /// small; scan the folder itself to see it. Always `nil` for files and packages.
    public let children: [DiskUsageItem]?
    /// What's inside a folder beyond ``children``.
    public let otherItems: OtherItems

    public var id: URL { url }
    public var name: String { url.lastPathComponent }
}

/// Adds up where the space in a folder goes, in one pass over everything inside it, hidden items included.
///
/// The result stays light even for a whole home folder: a folder lists at most ``maximumListed`` items, and a folder
/// smaller than ``detailThreshold`` keeps no list at all. Scanning such a folder on its own is quick, since it's small.
public struct DiskUsageScanner: Sendable {
    /// How far a scan has got.
    public struct Progress: Sendable, Hashable {
        public let bytes: Int64
        public let itemCount: Int
    }

    public let detailThreshold: Int64
    public let maximumListed: Int
    /// Libraries left unopened and counted as unreadable, so macOS doesn't ask for permission. `nil` opens everything.
    public let skipped: MediaLibraries?

    /// Folders deeper than this are measured as a whole, like small ones, so no tree can be too deep for the stack.
    static let maximumDepth = 64

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]
    private static let keySet = Set(keys)

    public init(detailThreshold: Int64 = 10_000_000, maximumListed: Int = 50, skipping skipped: MediaLibraries? = nil) {
        self.detailThreshold = detailThreshold
        self.maximumListed = maximumListed
        self.skipped = skipped
    }

    /// Measures `url` and everything inside it. `progress` is called now and then, on the calling thread.
    ///
    /// Symbolic links are never followed. Files and folders that only exist in the cloud (iCloud Drive, Dropbox and
    /// other File Provider apps) count as the space they take on this Mac and are never downloaded. Blocking; when
    /// cancelled, it stops early and returns what it counted so far.
    public func scan(_ url: URL, progress: (@Sendable (Progress) -> Void)? = nil) -> DiskUsageItem {
        if let skipped, skipped.contain(url) { return Self.unreadable(url, nil) }
        return Self.withoutDownloading {
            var tally = Tally(report: progress)
            do {
                let values = try url.resourceValues(forKeys: Self.keySet)
                return item(url, values, depth: 0, &tally)
            } catch {
                return Self.unreadable(url, error)
            }
        }
    }

    private func item(_ url: URL, _ values: URLResourceValues, depth: Int, _ tally: inout Tally) -> DiskUsageItem {
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            tally.add(bytes)
            return DiskUsageItem(
                url: url, kind: .file, bytes: bytes, isComplete: true, children: nil, otherItems: .none)
        }
        let isPackage = values.isPackage == true
        if let skipped, skipped.contain(url) {
            // Unreadable, like a folder macOS keeps closed: opening it is what would make macOS ask.
            tally.add(0)
            return DiskUsageItem(
                url: url, kind: isPackage ? .package : .folder, bytes: 0, isComplete: false,
                children: isPackage ? nil : [], otherItems: .none)
        }
        guard isPackage || depth >= Self.maximumDepth else { return folder(url, depth: depth, &tally) }

        let measurement = DirectorySize.measure(url)
        tally.add(measurement.bytes)
        return DiskUsageItem(
            url: url, kind: isPackage ? .package : .folder, bytes: measurement.bytes,
            isComplete: measurement.isComplete, children: nil, otherItems: .none)
    }

    private func folder(_ url: URL, depth: Int, _ tally: inout Tally) -> DiskUsageItem {
        // One entry at a time: a folder can hold a hundred thousand files (a framework's view cache, say), and
        // listing them all at once took over 1 GB of memory.
        let errors = ListingErrors(folder: url)
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Self.keys, options: [.skipsSubdirectoryDescendants],
                errorHandler: errors.record)
        else { return Self.unreadable(url, nil) }

        var listing = Listing(limit: maximumListed)
        while !Task.isCancelled {
            // Foundation hands out autoreleased objects for every entry. On a background thread they'd pile up until
            // the scan ends, so let go of them as it goes.
            let hasMore = autoreleasepool { () -> Bool in
                guard let child = enumerator.nextObject() as? URL else { return false }
                do {
                    listing.add(item(child, try child.resourceValues(forKeys: Self.keySet), depth: depth + 1, &tally))
                } catch {
                    if Self.isPermissionDenied(error) { listing.isComplete = false }
                }
                return true
            }
            if !hasMore { break }
        }
        if let error = errors.folderError, listing.isEmpty { return Self.unreadable(url, error) }
        tally.add(0)

        let isComplete = listing.isComplete && !errors.wasDenied
        // The folder being scanned always keeps its list; the ones inside it only when they're big enough to matter.
        guard depth == 0 || listing.bytes >= detailThreshold else {
            return DiskUsageItem(
                url: url, kind: .folder, bytes: listing.bytes, isComplete: isComplete, children: nil,
                otherItems: .none)
        }
        let children = listing.kept.sorted(by: Self.isListedBefore)
        return DiskUsageItem(
            url: url, kind: .folder, bytes: listing.bytes, isComplete: isComplete, children: children,
            otherItems: listing.others)
    }

    /// Biggest first; the same size sorts by name, like Finder.
    private static func isListedBefore(_ first: DiskUsageItem, _ second: DiskUsageItem) -> Bool {
        if first.bytes != second.bytes { return first.bytes > second.bytes }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    /// A folder Havus couldn't open. Gone or cloud-only counts as empty; refused by macOS counts as unreadable.
    private static func unreadable(_ url: URL, _ error: (any Error)?) -> DiskUsageItem {
        DiskUsageItem(
            url: url, kind: .folder, bytes: 0, isComplete: error.map { !isPermissionDenied($0) } ?? false,
            children: [], otherItems: .none)
    }

    fileprivate static func isPermissionDenied(_ error: any Error) -> Bool {
        FileRemover.reason(for: error) == .permissionDenied
    }

    /// Runs `work` with this thread's file access set to never download a cloud-only ("dataless") file or folder.
    /// Listing such a folder then fails instead of fetching its contents from the internet.
    static func withoutDownloading<T>(_ work: () -> T) -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let previous = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        setiopolicy_np(type, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { if previous >= 0 { setiopolicy_np(type, IOPOL_SCOPE_THREAD, previous) } }
        return work()
    }
}

/// What's in one folder: the biggest `limit` items, and totals for everything.
private struct Listing {
    let limit: Int
    private(set) var kept: [DiskUsageItem] = []
    private(set) var others = DiskUsageItem.OtherItems.none
    private(set) var bytes: Int64 = 0
    var isComplete = true
    /// Where in ``kept`` the smallest item is, once it's full.
    private var smallest = 0

    init(limit: Int) {
        self.limit = limit
    }

    var isEmpty: Bool { kept.isEmpty }

    mutating func add(_ item: DiskUsageItem) {
        bytes += item.bytes
        isComplete = isComplete && item.isComplete
        if kept.count < limit {
            kept.append(item)
            if kept.count == limit { findSmallest() }
        } else if limit > 0, item.bytes > kept[smallest].bytes {
            addToOthers(kept[smallest])
            kept[smallest] = item
            findSmallest()
        } else {
            addToOthers(item)
        }
    }

    private mutating func addToOthers(_ item: DiskUsageItem) {
        others = DiskUsageItem.OtherItems(count: others.count + 1, bytes: others.bytes + item.bytes)
    }

    private mutating func findSmallest() {
        smallest = kept.indices.min { kept[$0].bytes < kept[$1].bytes } ?? 0
    }
}

/// Errors from listing one folder. Only `folder` itself is opened, since the listing doesn't go deeper.
private final class ListingErrors {
    let folder: URL
    /// Why `folder` couldn't be opened, if it couldn't.
    private(set) var folderError: (any Error)?
    private(set) var wasDenied = false

    init(folder: URL) {
        self.folder = folder
    }

    func record(_ url: URL, _ error: any Error) -> Bool {
        if url.standardizedFileURL.path == folder.standardizedFileURL.path { folderError = error }
        if DiskUsageScanner.isPermissionDenied(error) { wasDenied = true }
        return true
    }
}

/// Running totals for ``DiskUsageScanner/Progress``, reported a few times a second.
private struct Tally {
    let report: (@Sendable (DiskUsageScanner.Progress) -> Void)?
    var bytes: Int64 = 0
    var itemCount = 0
    var lastReport: ContinuousClock.Instant?

    mutating func add(_ bytes: Int64) {
        self.bytes += bytes
        itemCount += 1
        guard let report else { return }
        let now = ContinuousClock.now
        if let lastReport, now - lastReport < .milliseconds(200) { return }
        lastReport = now
        report(DiskUsageScanner.Progress(bytes: self.bytes, itemCount: itemCount))
    }
}
