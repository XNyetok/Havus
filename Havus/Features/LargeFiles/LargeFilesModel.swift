import AppKit
import HavusCore
import Observation
import os

struct RemovalSummary: Equatable {
    let count: Int
    let bytes: Int64
    let failedCount: Int
}

@MainActor
@Observable
final class LargeFilesModel {
    enum Phase: Equatable {
        case idle, searching, results, removing
    }

    enum MinimumSize: Int64, CaseIterable, Identifiable {
        case mb50 = 50_000_000
        case mb100 = 100_000_000
        case mb500 = 500_000_000
        case gb1 = 1_000_000_000

        var id: Self { self }
        var label: String { Format.bytes(rawValue) }
    }

    enum LastOpened: Int, CaseIterable, Identifiable {
        case any = 0
        case threeMonths = 90
        case sixMonths = 180
        case oneYear = 365

        var id: Self { self }

        var cutoff: Date? {
            self == .any ? nil : Calendar.current.date(byAdding: .day, value: -rawValue, to: .now)
        }
    }

    var minimumSize: MinimumSize = .mb100
    var lastOpened: LastOpened = .any
    private(set) var phase: Phase = .idle
    private(set) var files: [LargeFile] = []
    var selection: Set<LargeFile.ID> = []
    private(set) var lastRemoval: RemovalSummary?
    /// The last search left the Photos library and the Music and TV folders out, for want of Full Disk Access.
    private(set) var skippedMediaLibraries = false

    @ObservationIgnored private var finder = LargeFileFinder()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var exclusions = ExclusionList()

    var selectedFiles: [LargeFile] { files.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Searches and removals use `list` from now on, and files it blocks go away right away.
    func setExclusions(_ list: ExclusionList) {
        guard list != exclusions else { return }
        exclusions = list
        files.removeAll { list.blocks($0.url) }
        selection.formIntersection(files.map(\.id))
    }

    func search() {
        task?.cancel()
        // Without Full Disk Access, even looking at a file in the Photos library or the Music and TV folders makes
        // macOS ask for a permission of their own, so the search leaves them out.
        let home = finder.home
        let skipped = FullDiskAccess.isGranted(home: home) ? nil : MediaLibraries(home: home)
        finder = LargeFileFinder(home: home, skipping: skipped)
        skippedMediaLibraries = skipped != nil
        let finder = self.finder
        let exclusions = self.exclusions
        let criteria = LargeFileFinder.Criteria(minimumSize: minimumSize.rawValue, notOpenedSince: lastOpened.cutoff)
        selection = []
        lastRemoval = nil
        phase = .searching
        let start = Date.now

        task = Task {
            var found = await Background.run { finder.find(criteria, excluding: exclusions) }
            guard !Task.isCancelled else { return }
            // The list may have changed during the search.
            if self.exclusions != exclusions {
                found.removeAll { self.exclusions.blocks($0.url) }
            }
            files = found
            phase = .results
            Log.scan.notice(
                "Large files: \(found.count) of \(Log.megabytes(criteria.minimumSize), format: .fixed(precision: 0)) MB or more, in \(Date.now.timeIntervalSince(start), format: .fixed(precision: 1)) s. Media libraries left out: \(skipped != nil ? "yes" : "no", privacy: .public)"
            )
        }
    }

    /// Keeps the list in step with the filters on screen: once a search has run, a filter change searches again.
    func filtersChanged() {
        guard phase == .results || phase == .searching else { return }
        search()
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = files.isEmpty ? .idle : .results
    }

    func toggle(_ file: LargeFile) {
        if selection.contains(file.id) {
            selection.remove(file.id)
        } else {
            selection.insert(file.id)
        }
    }

    func reveal(_ file: LargeFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func open(_ file: LargeFile) {
        NSWorkspace.shared.open(file.url)
    }

    func moveSelectionToTrash() {
        let targets = selectedFiles
        guard !targets.isEmpty else { return }
        let home = finder.home
        let exclusions = self.exclusions
        phase = .removing

        task = Task {
            let report = await Task.detached(priority: .userInitiated) {
                FileRemover(pathGuard: PathGuard(home: home, exclusions: exclusions))
                    .remove(targets.map(\.url), method: .moveToTrash, allowedRoots: [home])
            }.value
            let removed = Set(report.removed)
            files.removeAll { removed.contains($0.url) }
            selection.subtract(removed)
            lastRemoval = RemovalSummary(
                count: removed.count,
                bytes: targets.filter { removed.contains($0.url) }.reduce(0) { $0 + $1.size },
                failedCount: report.failures.count
            )
            Log.removal.notice(
                "Large files: moved \(removed.count) of \(targets.count) to the Trash, \(report.failures.count) failed")
            phase = .results
        }
    }
}
