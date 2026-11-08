import AppKit
import HavusCore
import Observation
import os

/// Tracks the macOS privacy permissions Havus depends on.
@MainActor
@Observable
final class PermissionCenter {
    private(set) var hasFullDiskAccess = FullDiskAccess.isGranted()

    func refresh() {
        let isGranted = FullDiskAccess.isGranted()
        if isGranted != hasFullDiskAccess {
            Log.app.notice("Full Disk Access is \(isGranted ? "on" : "off", privacy: .public) now")
        }
        hasFullDiskAccess = isGranted
    }

    func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    /// Needed on some Macs to move other apps to the Trash.
    func openAppManagementSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
