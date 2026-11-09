import AppKit
import HavusCore
import SwiftUI
import os

struct RootView: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(UpdateCenter.self) private var updates
    @Environment(ExclusionStore.self) private var exclusions
    @Environment(Navigator.self) private var navigator
    @Environment(ProblemReportCenter.self) private var problemReports
    @State private var systemJunk = JunkCleanerModel(group: .system)
    @State private var developerJunk = JunkCleanerModel(group: .developer)
    @State private var uninstaller = UninstallerModel()
    @State private var largeFiles = LargeFilesModel()
    @State private var diskUsage = DiskUsageModel()
    @State private var startupItems = StartupItemsModel()
    /// Whether the welcome sheet was answered to the end.
    @AppStorage("Onboarding.done") private var hasOnboarded = false
    @State private var isShowingOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                row(.overview)
                Section("Bersihin") {
                    row(.systemJunk, badge: systemJunk.badge)
                    row(.developerJunk, badge: developerJunk.badge)
                }
                Section("Kelola") {
                    row(.uninstaller)
                    row(.largeFiles)
                    row(.diskUsage)
                    row(.startupItems)
                }
            }
            // No wider than it opens: the window's minimum width counts on it (see HavusApp), and macOS remembers the
            // width between launches. Every name fits from the minimum up.
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 250)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AboutSidebarFooter(isSelected: selection == .about) { selection = .about }
            }
        } detail: {
            // The page's name and what it's for sit in the toolbar, like in Finder and System Settings, so the page
            // itself starts with its content.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(Text(selection.title))
                .navigationSubtitle(Text(selection.subtitle))
        }
        .updateCheckAlert(updates)
        .problemReportAlert(problemReports)
        // Once, on the first launch. Someone who already answered the update question before the sheet existed has
        // been using Havus, so they skip it. A new crash report isn't offered on top of the sheet: it waits for the
        // next launch.
        .onAppear {
            isShowingOnboarding = !hasOnboarded && !updates.hasChosenAutomaticChecks
            if !isShowingOnboarding {
                problemReports.offerNewCrashReport()
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView {
                hasOnboarded = true
                isShowingOnboarding = false
            }
        }
        // Every page scans and removes with the latest list, and drops results the user just excluded.
        .onChange(of: exclusions.list, initial: true) { _, list in
            Log.app.notice("Exclusion list: \(list.urls.count) items")
            systemJunk.setExclusions(list)
            developerJunk.setExclusions(list)
            uninstaller.setExclusions(list)
            largeFiles.setExclusions(list)
            diskUsage.setExclusions(list)
            startupItems.setExclusions(list)
        }
        // A disk map from before a cleanup may still show what it removed, and Peta Disk says so.
        .onChange(of: systemJunk.removals + developerJunk.removals + largeFiles.removals + uninstaller.removals) {
            diskUsage.noteRemoval()
        }
        .task { updates.checkIfDue() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            updates.checkIfDue()
        }
    }

    /// The page on screen. The menu bar can change it too, so it lives in the shared `Navigator`.
    private var selection: SidebarItem {
        get { navigator.selection }
        nonmutating set { navigator.selection = newValue }
    }

    /// The sidebar never ends up with nothing selected.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { if let item = $0 { selection = item } })
    }

    private func row(_ item: SidebarItem, badge: String? = nil) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge.map { Text($0) })
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview:
            OverviewView(
                tools: OverviewTools(
                    systemJunk: systemJunk, developerJunk: developerJunk, uninstaller: uninstaller,
                    largeFiles: largeFiles, diskUsage: diskUsage, startupItems: startupItems)
            ) { selection = $0 }
        case .systemJunk:
            JunkCleanerView(model: systemJunk, page: .systemJunk)
        case .developerJunk:
            JunkCleanerView(model: developerJunk, page: .developerJunk)
        case .uninstaller:
            UninstallerView(model: uninstaller)
        case .largeFiles:
            LargeFilesView(model: largeFiles)
        case .diskUsage:
            DiskUsageView(model: diskUsage)
        case .startupItems:
            StartupItemsView(model: startupItems) { app in
                uninstaller.show(app)
                selection = .uninstaller
            }
        case .about:
            AboutView()
        }
    }
}
