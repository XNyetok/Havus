import AppKit
import HavusCore
import Observation
import os

struct CleanupSummary: Equatable, Sendable {
    var trashedBytes: Int64 = 0
    var deletedBytes: Int64 = 0
    var failedCount = 0
    var trashNeedsPermission = false
}

/// State for one junk page ("Sampah Sistem" or "Sampah Developer").
@MainActor
@Observable
final class JunkCleanerModel {
    enum Phase: Equatable {
        case idle
        case scanning(finished: Int, total: Int)
        case results
        case cleaning
        case finished(CleanupSummary)
    }

    let group: JunkRule.Group
    private(set) var phase: Phase = .idle
    private(set) var results: [JunkScanResult] = []
    var selection: Set<JunkItem.ID> = []
    /// Goes up after each cleanup that removed something, so Peta Disk can tell when its map is older.
    private(set) var removals = 0

    @ObservationIgnored private let scanner: JunkScanner
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var exclusions = ExclusionList()

    init(group: JunkRule.Group, scanner: JunkScanner = JunkScanner()) {
        self.group = group
        self.scanner = scanner
    }

    private var rules: [JunkRule] { scanner.rules.filter { $0.group == group } }

    /// Results worth showing: something to clean, or a location macOS kept us out of.
    var visibleResults: [JunkScanResult] {
        results.filter { !$0.items.isEmpty || $0.status == .noPermission }
    }

    var totalSize: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var selectedItems: [JunkItem] { results.flatMap(\.items).filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var selectionIncludesPermanentDeletion: Bool {
        results.contains { result in
            result.rule.removal == .deletePermanently && result.items.contains { selection.contains($0.id) }
        }
    }

    /// Sidebar badge after a scan, e.g. "3,2 GB".
    var badge: String? {
        guard phase == .results, totalSize > 0 else { return nil }
        return Format.bytes(totalSize)
    }

    func selectionState(of result: JunkScanResult) -> CheckState {
        let selected = result.items.filter { selection.contains($0.id) }.count
        if selected == 0 { return .off }
        return selected == result.items.count ? .on : .mixed
    }

    func toggle(_ item: JunkItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func toggleAll(in result: JunkScanResult) {
        let ids = Set(result.items.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    /// Scans and removals use `list` from now on, and results it blocks go away right away.
    func setExclusions(_ list: ExclusionList) {
        guard list != exclusions else { return }
        exclusions = list
        results = results.map { $0.excluding(list) }
        selection.formIntersection(results.flatMap(\.items).map(\.id))
    }

    // MARK: - Scanning

    func scan() {
        task?.cancel()
        let rules = self.rules
        let scanner = self.scanner
        let exclusions = self.exclusions
        let runningApps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        results = []
        selection = []
        phase = .scanning(finished: 0, total: rules.count)
        let start = Date.now

        task = Task {
            await withTaskGroup(of: JunkScanResult.self) { group in
                for rule in rules {
                    group.addTask { scanner.scan(rule, inUseNames: runningApps, excluding: exclusions) }
                }
                for await scanned in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    // The list may have changed while this rule was being scanned.
                    let result = self.exclusions == exclusions ? scanned : scanned.excluding(self.exclusions)
                    results.append(result)
                    if result.rule.safety == .safe {
                        selection.formUnion(result.items.filter { !$0.isInUse }.map(\.id))
                    }
                    phase = .scanning(finished: results.count, total: rules.count)
                }
            }
            guard !Task.isCancelled else { return }
            results.sort { $0.totalSize > $1.totalSize }
            phase = .results
            logScan(since: start)
        }
    }

    private func logScan(since start: Date) {
        let itemCount = results.reduce(0) { $0 + $1.items.count }
        let unreadable = results.filter { $0.status == .noPermission }.map(\.rule.id.rawValue)
        Log.scan.notice(
            "\(self.group.rawValue, privacy: .public) junk: \(itemCount) items, \(Log.megabytes(self.totalSize), format: .fixed(precision: 1)) MB, from \(self.results.count) rules in \(Date.now.timeIntervalSince(start), format: .fixed(precision: 1)) s. No permission for: \(unreadable.isEmpty ? "none" : unreadable.joined(separator: ", "), privacy: .public)"
        )
    }

    func cancel() {
        task?.cancel()
        task = nil
        results = []
        selection = []
        phase = .idle
    }

    // MARK: - Cleaning

    func clean() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let rules = Dictionary(uniqueKeysWithValues: scanner.rules.map { ($0.id, $0) })
        let home = scanner.home
        let exclusions = self.exclusions
        phase = .cleaning

        task = Task {
            let summary = await Task.detached(priority: .userInitiated) {
                JunkCleanerModel.remove(items, rules: rules, home: home, exclusions: exclusions)
            }.value
            Log.removal.notice(
                "\(self.group.rawValue, privacy: .public) junk: cleaned \(items.count) items, \(Log.megabytes(summary.trashedBytes), format: .fixed(precision: 1)) MB to the Trash, \(Log.megabytes(summary.deletedBytes), format: .fixed(precision: 1)) MB deleted, \(summary.failedCount) removals failed"
            )
            results = []
            selection = []
            if summary.trashedBytes + summary.deletedBytes > 0 {
                removals += 1
            }
            phase = .finished(summary)
        }
    }

    func emptyTrash() {
        guard let rule = scanner.rules.first(where: { $0.id == .trash }) else { return }
        let scanner = self.scanner
        let exclusions = self.exclusions
        phase = .cleaning

        task = Task {
            let summary = await Task.detached(priority: .userInitiated) {
                let result = scanner.scan(rule, excluding: exclusions)
                guard result.status != .noPermission else { return CleanupSummary(trashNeedsPermission: true) }
                return JunkCleanerModel.remove(
                    result.items, rules: [rule.id: rule], home: scanner.home, exclusions: exclusions)
            }.value
            if summary.trashNeedsPermission {
                Log.removal.notice("Couldn't empty the Trash: it needs Full Disk Access")
            } else {
                Log.removal.notice(
                    "Emptied the Trash: \(Log.megabytes(summary.deletedBytes), format: .fixed(precision: 1)) MB deleted, \(summary.failedCount) removals failed"
                )
            }
            if summary.deletedBytes > 0 {
                removals += 1
            }
            phase = .finished(summary)
        }
    }

    /// Runs off the main actor. Every removal goes through `FileRemover`, which checks `PathGuard`.
    nonisolated private static func remove(
        _ items: [JunkItem], rules: [JunkRule.ID: JunkRule], home: URL, exclusions: ExclusionList
    ) -> CleanupSummary {
        let remover = FileRemover(pathGuard: PathGuard(home: home, exclusions: exclusions))
        var summary = CleanupSummary()
        for item in items {
            guard let rule = rules[item.ruleID] else { continue }
            let report = remover.remove(
                item.removalTargets, method: rule.removal, allowedRoots: [rule.location(in: home)])
            summary.failedCount += report.failures.count
            guard report.failures.isEmpty else { continue }
            switch rule.removal {
            case .moveToTrash: summary.trashedBytes += item.size
            case .deletePermanently: summary.deletedBytes += item.size
            }
        }
        return summary
    }
}
