import AppKit
import HavusCore
import Observation
import os

struct UninstallOutcome: Equatable {
    let appName: String
    let removedApp: Bool
    let removedLeftovers: Int
    let bytes: Int64
    let failedCount: Int
    /// macOS refused to move the app bundle itself.
    let appBlocked: Bool
}

@MainActor
@Observable
final class UninstallerModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoadingApps = false
    private(set) var sizes: [InstalledApp.ID: Int64] = [:]
    var searchText = ""

    private(set) var selectedAppID: InstalledApp.ID?
    private(set) var leftovers: [Leftover] = []
    private(set) var isLoadingLeftovers = false
    var leftoverSelection: Set<Leftover.ID> = []
    var includesApp = true
    /// The selected app is on the exclusion list, so it can't be removed. Its leftovers still can.
    private(set) var isSelectedAppExcluded = false
    private(set) var isSelectedAppRunning = false
    private(set) var isRemoving = false
    private(set) var outcome: UninstallOutcome?

    @ObservationIgnored private let catalog = AppCatalog()
    @ObservationIgnored private let finder = LeftoverFinder()
    @ObservationIgnored private var appsTask: Task<Void, Never>?
    @ObservationIgnored private var leftoverTask: Task<Void, Never>?
    @ObservationIgnored private var exclusions = ExclusionList()
    /// An app to select once the list is loaded, asked for by ``show(_:)``.
    @ObservationIgnored private var appToShow: InstalledApp?

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var selectedLeftovers: [Leftover] { leftovers.filter { leftoverSelection.contains($0.id) } }

    var selectedBytes: Int64 {
        let appBytes = includesApp ? (selectedAppID.flatMap { sizes[$0] } ?? 0) : 0
        return selectedLeftovers.reduce(appBytes) { $0 + $1.size }
    }

    var canRemove: Bool {
        selectedApp != nil && !isSelectedAppRunning && !isRemoving && !isLoadingLeftovers
            && (includesApp || !leftoverSelection.isEmpty)
    }

    // MARK: - Loading

    func loadAppsIfNeeded() {
        guard apps.isEmpty, !isLoadingApps else { return }
        isLoadingApps = true
        let catalog = self.catalog

        appsTask = Task {
            let found = await Task.detached(priority: .userInitiated) { catalog.installedApps() }.value
            Log.scan.notice("Uninstaller: \(found.count) apps")
            apps = found
            isLoadingApps = false
            if let app = appToShow {
                appToShow = nil
                select(matching: app)
            }
            await measureSizes(of: found)
        }
    }

    /// Selects `app`, for example from Jalan Otomatis. Waits for the list when it isn't loaded yet.
    func show(_ app: InstalledApp) {
        searchText = ""
        if apps.isEmpty {
            appToShow = app
            loadAppsIfNeeded()
        } else {
            select(matching: app)
        }
    }

    /// The app in the list at the same location, if it's still there.
    private func select(matching app: InstalledApp) {
        let path = app.url.standardizedFileURL.path(percentEncoded: false)
        if let match = apps.first(where: { $0.url.standardizedFileURL.path(percentEncoded: false) == path }) {
            select(match.id)
        }
    }

    /// Measures app sizes a few at a time, so the list fills in progressively.
    private func measureSizes(of apps: [InstalledApp]) async {
        await withTaskGroup(of: (InstalledApp.ID, Int64).self) { group in
            var pending = apps.makeIterator()
            for _ in 0..<3 {
                guard let app = pending.next() else { break }
                group.addTask { (app.id, DirectorySize.allocatedSize(of: app.url)) }
            }
            for await (id, size) in group {
                sizes[id] = size
                if let app = pending.next() {
                    group.addTask { (app.id, DirectorySize.allocatedSize(of: app.url)) }
                }
            }
        }
    }

    func select(_ id: InstalledApp.ID?) {
        leftoverTask?.cancel()
        selectedAppID = id
        leftovers = []
        leftoverSelection = []
        isSelectedAppExcluded = selectedApp.map { self.exclusions.blocks($0.url) } ?? false
        includesApp = !isSelectedAppExcluded
        outcome = nil
        refreshRunningState()
        guard let app = selectedApp else {
            isLoadingLeftovers = false
            return
        }

        isLoadingLeftovers = true
        let finder = self.finder
        let exclusions = self.exclusions
        let otherApps = Set(apps.map(\.bundleIdentifier)).subtracting([app.bundleIdentifier])
        leftoverTask = Task {
            var found = await Background.run {
                finder.leftovers(for: app, otherBundleIdentifiers: otherApps, excluding: exclusions)
            }
            guard !Task.isCancelled, selectedAppID == app.id else { return }
            // The list may have changed while Havus was looking.
            if self.exclusions != exclusions {
                found.removeAll { self.exclusions.blocks($0.url) }
            }
            leftovers = found
            // Name-based matches need a human look, so they start unselected.
            leftoverSelection = Set(found.filter { $0.match == .bundleIdentifier }.map(\.id))
            isLoadingLeftovers = false
            Log.scan.notice(
                "Uninstaller: \(found.count) leftovers of \(app.bundleIdentifier, privacy: .private(mask: .hash)), \(self.leftoverSelection.count) by bundle identifier"
            )
        }
    }

    func toggleLeftover(_ leftover: Leftover) {
        if leftoverSelection.contains(leftover.id) {
            leftoverSelection.remove(leftover.id)
        } else {
            leftoverSelection.insert(leftover.id)
        }
    }

    /// Finding and removing use `list` from now on, and leftovers it blocks go away right away.
    func setExclusions(_ list: ExclusionList) {
        guard list != exclusions else { return }
        exclusions = list
        leftovers.removeAll { list.blocks($0.url) }
        leftoverSelection.formIntersection(leftovers.map(\.id))
        isSelectedAppExcluded = selectedApp.map { list.blocks($0.url) } ?? false
        if isSelectedAppExcluded {
            includesApp = false
        }
    }

    // MARK: - Running apps

    func refreshRunningState() {
        guard let app = selectedApp else {
            isSelectedAppRunning = false
            return
        }
        isSelectedAppRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: app.bundleIdentifier
        ).isEmpty
    }

    func quitSelectedApp() {
        guard let app = selectedApp else { return }
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier) {
            running.terminate()
        }
    }

    // MARK: - Removing

    func removeSelection() {
        // The app may have been opened since it was selected.
        refreshRunningState()
        guard canRemove, let app = selectedApp else { return }
        let appTargets = includesApp && !isSelectedAppExcluded ? [app.url] : []
        let leftoverTargets = selectedLeftovers
        let appSize = sizes[app.id] ?? 0
        let appRoots = catalog.searchRoots
        let leftoverRoots = finder.searchRoots
        let exclusions = self.exclusions
        isRemoving = true

        Task {
            let (appReport, leftoverReport) = await Task.detached(priority: .userInitiated) {
                let remover = FileRemover(pathGuard: PathGuard(exclusions: exclusions))
                return (
                    remover.remove(appTargets, method: .moveToTrash, allowedRoots: appRoots),
                    remover.remove(leftoverTargets.map(\.url), method: .moveToTrash, allowedRoots: leftoverRoots)
                )
            }.value

            let removedApp = !appReport.removed.isEmpty
            let removedLeftoverURLs = Set(leftoverReport.removed)
            Log.removal.notice(
                "Uninstaller: \(app.bundleIdentifier, privacy: .private(mask: .hash)): app moved to the Trash: \(removedApp ? "yes" : appTargets.isEmpty ? "not chosen" : "no", privacy: .public), leftovers moved: \(removedLeftoverURLs.count) of \(leftoverTargets.count), \(appReport.failures.count + leftoverReport.failures.count) failed"
            )
            let leftoverBytes = leftoverTargets.filter { removedLeftoverURLs.contains($0.url) }.reduce(0) {
                $0 + $1.size
            }
            if removedApp {
                apps.removeAll { $0.id == app.id }
            }
            selectedAppID = nil
            leftovers = []
            leftoverSelection = []
            isRemoving = false
            outcome = UninstallOutcome(
                appName: app.name,
                removedApp: removedApp,
                removedLeftovers: removedLeftoverURLs.count,
                bytes: (removedApp ? appSize : 0) + leftoverBytes,
                failedCount: appReport.failures.count + leftoverReport.failures.count,
                appBlocked: !appReport.failures.isEmpty
            )
        }
    }
}
