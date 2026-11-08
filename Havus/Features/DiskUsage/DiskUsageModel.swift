import AppKit
import HavusCore
import Observation
import os

/// State for "Peta Disk": where the space in the home folder goes. Read-only: nothing here removes anything.
@MainActor
@Observable
final class DiskUsageModel {
    enum Phase: Equatable {
        case idle, scanning, results
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

    @ObservationIgnored private var scanner = DiskUsageScanner()
    @ObservationIgnored private let home = URL.homeDirectory
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Every scan gets the next number, so progress from a scan that was replaced never shows up.
    @ObservationIgnored private var scansStarted = 0

    var root: DiskUsageItem? { path.first }
    var current: DiskUsageItem? { path.last }

    func setExclusions(_ list: ExclusionList) {
        exclusions = list
    }

    func isExcluded(_ item: DiskUsageItem) -> Bool {
        exclusions.covers(item.url)
    }

    /// Measures the whole home folder again and starts over at its top.
    func scan() {
        task?.cancel()
        scansStarted += 1
        let scan = scansStarted
        // Without Full Disk Access, opening the Photos library or the Music and TV folders makes macOS ask for a
        // permission of their own, so the map leaves them closed and shows them as unreadable.
        scanner = DiskUsageScanner(skipping: FullDiskAccess.isGranted(home: home) ? nil : MediaLibraries(home: home))
        let scanner = self.scanner
        let home = self.home
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
            path = [root]
            phase = .results
            Log.scan.notice(
                "Disk map: \(Log.megabytes(root.bytes), format: .fixed(precision: 1)) MB in the home folder, in \(Date.now.timeIntervalSince(start), format: .fixed(precision: 1)) s. Everything readable: \(root.isComplete ? "yes" : "no", privacy: .public)"
            )
        }
    }

    /// Stops a scan. Results from an earlier scan, if any, stay on screen.
    func cancel() {
        task?.cancel()
        task = nil
        opening = nil
        phase = path.isEmpty ? .idle : .results
    }

    /// Shows what's inside `item`. A small folder is scanned first, since the map keeps no list for it.
    func open(_ item: DiskUsageItem) {
        guard item.kind == .folder, opening == nil, phase == .results else { return }
        if item.children != nil {
            path.append(item)
            return
        }
        opening = item.id
        let scanner = self.scanner
        task = Task {
            let scanned = await Background.run { scanner.scan(item.url) }
            guard !Task.isCancelled else { return }
            opening = nil
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

    private func stopOpening() {
        guard opening != nil else { return }
        task?.cancel()
        task = nil
        opening = nil
    }
}
