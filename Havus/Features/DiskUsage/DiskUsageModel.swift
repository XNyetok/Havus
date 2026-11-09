import AppKit
import HavusCore
import Observation
import os

/// State for "Peta Disk": where the space in the home folder goes. Read-only: nothing here removes anything.
///
/// Every scan is saved, and the page opens with the last one, saying how old it is. Havus never scans the home folder
/// by itself: without Full Disk Access, reading some folders makes macOS ask for permission, so the user starts it.
@MainActor
@Observable
final class DiskUsageModel {
    enum Phase: Equatable {
        /// `loading`: reading the map the last scan saved.
        case idle, loading, scanning, results
    }

    private(set) var phase: Phase = .idle
    /// How far the scan of the home folder has got.
    private(set) var progress: DiskUsageScanner.Progress?
    /// The home folder first, the folder on screen last.
    private(set) var path: [DiskUsageItem] = []
    /// A small folder being scanned before it opens. Its row shows a spinner in the meantime.
    private(set) var opening: DiskUsageItem.ID?
    /// Only for the "Dikecualiin" tag: the map measures excluded items too, since it removes nothing.
    private(set) var exclusions = ExclusionList()
    /// When the scan of the map on screen started.
    private(set) var mapDate: Date?
    /// Whether Full Disk Access was on during that scan.
    private(set) var mapHadFullDiskAccess = true
    /// When another page last moved or deleted files. A map from before then may still show them.
    private(set) var lastRemoval: Date?
    /// Folders scanned when they were opened, since the map keeps no list for them, and when.
    private(set) var openedScans: [DiskUsageItem.ID: Date] = [:]
    /// Folders on the map that were gone by the time they were opened.
    private(set) var goneFolders: Set<DiskUsageItem.ID> = []

    @ObservationIgnored private var scanner = DiskUsageScanner()
    @ObservationIgnored private let home = URL.homeDirectory
    @ObservationIgnored private let savedMap: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Every scan gets the next number, so progress from a scan that was replaced never shows up.
    @ObservationIgnored private var scansStarted = 0
    /// The home folder's size at the last scan, when that scan could read as much as this one.
    @ObservationIgnored private var expectedBytes: Int64?
    @ObservationIgnored private var hasLookedForSavedMap = false

    /// `~/Library/Application Support/<bundle ID>/DiskMap.plist`. Debug builds have a bundle ID of their own, so their
    /// own map.
    nonisolated static var savedMapFile: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "id.nyetok.havus", directoryHint: .isDirectory)
            .appending(path: "DiskMap.plist", directoryHint: .notDirectory)
    }

    init(savedMap: URL = DiskUsageModel.savedMapFile, defaults: UserDefaults = .standard) {
        self.savedMap = savedMap
        self.defaults = defaults
        lastRemoval = defaults.object(forKey: Key.lastRemoval) as? Date
    }

    var root: DiskUsageItem? { path.first }
    var current: DiskUsageItem? { path.last }

    /// How far a scan has got, judged by the size of the home folder at the last scan. `nil` without one.
    var progressFraction: Double? {
        guard let progress, let expectedBytes, expectedBytes > 0 else { return nil }
        // Never full while it's still counting: the folder may have grown.
        return min(Double(progress.bytes) / Double(expectedBytes), 0.99)
    }

    func setExclusions(_ list: ExclusionList) {
        exclusions = list
    }

    func isExcluded(_ item: DiskUsageItem) -> Bool {
        exclusions.covers(item.url)
    }

    /// When `folder` was scanned: on its own when it was opened, or else with the map.
    func scanDate(of folder: DiskUsageItem) -> Date? {
        openedScans[folder.id] ?? mapDate
    }

    /// Havus moved or deleted files on another page after `folder` was scanned.
    func predatesRemoval(_ folder: DiskUsageItem) -> Bool {
        guard let lastRemoval, let date = scanDate(of: folder) else { return false }
        return lastRemoval > date
    }

    func isGone(_ folder: DiskUsageItem) -> Bool {
        goneFolders.contains(folder.id)
    }

    /// Opens the map the last scan saved, the first time the page shows up. Never scans.
    func showSavedMap() {
        guard !hasLookedForSavedMap, phase == .idle else { return }
        hasLookedForSavedMap = true
        guard FileManager.default.fileExists(atPath: savedMap.path(percentEncoded: false)) else { return }
        let savedMap = self.savedMap
        let home = self.home
        phase = .loading

        task = Task {
            let snapshot = await Background.run { DiskUsageSnapshot.load(from: savedMap, of: home) }
            guard !Task.isCancelled, phase == .loading else { return }
            guard let snapshot else {
                Log.scan.notice("Disk map: the saved map can't be used, so the page waits for a scan")
                phase = .idle
                return
            }
            // Folders the map keeps no list for are scanned when they're opened, as the permission stands now.
            scanner = Self.scanner(for: home, hasFullDiskAccess: FullDiskAccess.isGranted(home: home))
            show(snapshot)
            Log.scan.notice(
                "Disk map: showing the saved map, \(Log.megabytes(snapshot.root.bytes), format: .fixed(precision: 1)) MB, scanned \(Date.now.timeIntervalSince(snapshot.date) / 3600, format: .fixed(precision: 1)) h ago. Full Disk Access then: \(snapshot.hadFullDiskAccess ? "on" : "off", privacy: .public)"
            )
        }
    }

    /// Measures the whole home folder again and starts over at its top. The map on screen stays until it's done.
    func scan() {
        task?.cancel()
        scansStarted += 1
        let scan = scansStarted
        let hasFullDiskAccess = FullDiskAccess.isGranted(home: home)
        scanner = Self.scanner(for: home, hasFullDiskAccess: hasFullDiskAccess)
        let scanner = self.scanner
        let home = self.home
        expectedBytes = mapHadFullDiskAccess == hasFullDiskAccess ? root?.bytes : nil
        progress = nil
        opening = nil
        phase = .scanning

        let report: @Sendable (DiskUsageScanner.Progress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.scansStarted == scan, self.phase == .scanning else { return }
                self.progress = progress
            }
        }
        let start = Date.now
        task = Task {
            let root = await Background.run { scanner.scan(home, progress: report) }
            guard !Task.isCancelled else { return }
            let snapshot = DiskUsageSnapshot(root: root, date: start, hadFullDiskAccess: hasFullDiskAccess)
            show(snapshot)
            Log.scan.notice(
                "Disk map: \(Log.megabytes(root.bytes), format: .fixed(precision: 1)) MB in the home folder, in \(Date.now.timeIntervalSince(start), format: .fixed(precision: 1)) s. Everything readable: \(root.isComplete ? "yes" : "no", privacy: .public)"
            )
            save(snapshot)
        }
    }

    /// Stops a scan. Results from an earlier scan, if any, stay on screen.
    func cancel() {
        task?.cancel()
        task = nil
        opening = nil
        phase = path.isEmpty ? .idle : .results
    }

    /// Shows what's inside `item`. A small folder is scanned first, since the map keeps no list for it, and so is one
    /// that's gone since the map was made, so it shows up as it is now.
    func open(_ item: DiskUsageItem) {
        guard item.kind == .folder, opening == nil, phase == .results else { return }
        if item.children != nil, FileManager.default.fileExists(atPath: item.url.path(percentEncoded: false)) {
            path.append(item)
            return
        }
        opening = item.id
        let scanner = self.scanner
        task = Task {
            let (scanned, isGone) = await Background.run {
                (scanner.scan(item.url), !FileManager.default.fileExists(atPath: item.url.path(percentEncoded: false)))
            }
            guard !Task.isCancelled else { return }
            opening = nil
            openedScans[item.id] = .now
            if isGone {
                goneFolders.insert(item.id)
            }
            path.append(scanned)
        }
    }

    /// Goes back to the folder at `index` in ``path``.
    func goBack(to index: Int) {
        guard path.indices.contains(index), index < path.count - 1 else { return }
        stopOpening()
        path.removeSubrange((index + 1)...)
    }

    func goUp() {
        goBack(to: path.count - 2)
    }

    func reveal(_ item: DiskUsageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Another page moved or deleted files. Kept between launches, like the map.
    func noteRemoval() {
        let now = Date.now
        lastRemoval = now
        defaults.set(now, forKey: Key.lastRemoval)
    }

    private func show(_ snapshot: DiskUsageSnapshot) {
        path = [snapshot.root]
        mapDate = snapshot.date
        mapHadFullDiskAccess = snapshot.hadFullDiskAccess
        openedScans = [:]
        goneFolders = []
        phase = .results
    }

    private func save(_ snapshot: DiskUsageSnapshot) {
        let savedMap = self.savedMap
        Task.detached(priority: .utility) {
            do {
                try snapshot.save(to: savedMap)
            } catch {
                let error = error as NSError
                Log.scan.error("Disk map: couldn't save the map: \(error.domain, privacy: .public) \(error.code)")
            }
        }
    }

    private func stopOpening() {
        guard opening != nil else { return }
        task?.cancel()
        task = nil
        opening = nil
    }

    /// Without Full Disk Access, opening the Photos library or the Music and TV folders makes macOS ask for a
    /// permission of their own, so the map leaves them closed and shows them as unreadable.
    private static func scanner(for home: URL, hasFullDiskAccess: Bool) -> DiskUsageScanner {
        DiskUsageScanner(skipping: hasFullDiskAccess ? nil : MediaLibraries(home: home))
    }

    private enum Key {
        static let lastRemoval = "DiskMap.lastRemoval"
    }
}
