import HavusCore
import SwiftUI
import os

@main
struct HavusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var navigator = Navigator()
    @State private var permissions = PermissionCenter()
    @State private var updates = UpdateCenter()
    @State private var exclusions = ExclusionStore()
    @State private var problemReports = ProblemReportCenter()

    var body: some Scene {
        Window("Havus", id: "main") {
            RootView()
                .environment(navigator)
                .environment(permissions)
                .environment(updates)
                .environment(exclusions)
                .environment(problemReports)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            AboutCommands(navigator: navigator)
            UpdateCommands(updates: updates)
            ProblemReportCommands(reports: problemReports)
        }

        Settings {
            SettingsView()
                .environment(permissions)
                .environment(updates)
                .environment(exclusions)
        }
    }
}

/// **Havus → Tentang Havus** opens the page in the main window, in place of the small standard panel.
struct AboutCommands: Commands {
    let navigator: Navigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Tentang Havus") {
                navigator.selection = .about
                openWindow(id: "main")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The first line of each session in the log, with what a problem report would ask for.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice(
            "Havus \(Bundle.main.versionAndBuild ?? "?", privacy: .public) started on \(MacInfo.osVersion, privacy: .public), \(MacInfo.isAppleSilicon ? "Apple silicon" : "Intel", privacy: .public), Full Disk Access \(FullDiskAccess.isGranted() ? "on" : "off", privacy: .public)"
        )
    }

    /// Havus is a single-window utility: closing the window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
