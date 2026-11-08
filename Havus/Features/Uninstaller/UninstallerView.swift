import AppKit
import HavusCore
import SwiftUI

struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @State private var isConfirming = false

    var body: some View {
        HSplitView {
            // HSplitView opens the list at its minimum width, and the divider runs up through the toolbar, so the
            // minimum is what keeps the page's subtitle there clear of it ("Remove apps together with their leftover
            // files" takes 259 points).
            appList
                .frame(minWidth: 270, idealWidth: 270, maxWidth: 360)
            detail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Cari aplikasi")
        .task {
            model.loadAppsIfNeeded()
            model.refreshRunningState()
        }
        // Keep the running-app warning accurate while this page is open.
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
        ) {
            _ in model.refreshRunningState()
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        ) {
            _ in model.refreshRunningState()
        }
        .confirmationDialog(confirmationTitle, isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Pindahin ke Tong Sampah", role: .destructive) { model.removeSelection() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Semuanya dipindah ke Tong Sampah, jadi masih bisa dibalikin.")
        }
    }

    private var confirmationTitle: Text {
        let name = model.selectedApp?.name ?? ""
        let count = model.selectedLeftovers.count
        return model.includesApp
            ? Text("Hapus \(name) dan \(count) file sisanya?")
            : Text("Hapus \(count) file sisa \(name)?")
    }

    @ViewBuilder
    private var appList: some View {
        if model.isLoadingApps && model.apps.isEmpty {
            ProgressView("Lagi ngumpulin daftar aplikasi…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.filteredApps, selection: Binding(get: { model.selectedAppID }, set: { model.select($0) })) {
                app in
                AppRow(app: app, size: model.sizes[app.id])
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        PhaseContent(key: detailKey) {
            if let app = model.selectedApp {
                AppDetail(app: app, model: model) { isConfirming = true }
            } else if let outcome = model.outcome {
                OutcomeView(outcome: outcome)
            } else {
                EmptyState(
                    symbol: SidebarItem.uninstaller.symbol,
                    title: Text("Pilih aplikasi"),
                    message: Text("Pilih app di sebelah kiri buat lihat file-file sisanya."))
            }
        }
    }

    /// Each app gets its own key, so switching apps crossfades too.
    private var detailKey: String {
        if let app = model.selectedApp { return app.id.absoluteString }
        return model.outcome == nil ? "none" : "outcome"
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let size: Int64?

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            FileIcon(url: app.url)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                Group {
                    if let size {
                        Text(Format.bytes(size))
                    } else {
                        Text("Ngitung ukuran…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AppDetail: View {
    let app: InstalledApp
    let model: UninstallerModel
    let onRemove: () -> Void
    @Environment(ExclusionStore.self) private var exclusions
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.l) {
                    header
                    if model.isSelectedAppRunning {
                        NoticeBanner(
                            tone: .warning, symbol: "exclamationmark.triangle.fill",
                            message: Text("\(app.name) lagi jalan. Tutup dulu sebelum dihapus ya.")
                        ) {
                            Button("Tutup Aplikasi") { model.quitSelectedApp() }
                        }
                    }
                    if !permissions.hasFullDiskAccess, model.leftovers.contains(where: { !$0.isFullyReadable }) {
                        NoticeBanner(
                            tone: .warning, symbol: "lock.fill",
                            message: Text(
                                "Ada file sisa yang nggak bisa dibaca Havus, jadi ukurannya belum lengkap. Nyalain Akses Disk Penuh biar kebaca semua."
                            )
                        ) {
                            Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                        }
                    }
                    components
                }
                .padding(Design.pageMargin)
            }
            ActionBar {
                Text("\(Format.bytes(model.selectedBytes)) bakal dipindah ke Tong Sampah")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Design.Motion.quick, value: model.selectedBytes)
            } trailing: {
                Button(removeTitle, action: onRemove)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canRemove)
            }
        }
    }

    private var removeTitle: LocalizedStringKey {
        model.includesApp ? "Hapus \(app.name)" : "Hapus \(model.selectedLeftovers.count) file sisa"
    }

    private var header: some View {
        HStack(spacing: Design.Spacing.l) {
            FileIcon(url: app.url, size: 56)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                Group {
                    if let version = app.version {
                        Text("Versi \(version) · \(app.bundleIdentifier)")
                    } else {
                        Text(app.bundleIdentifier)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComponentRow(
                title: "Aplikasi", path: Format.path(app.url), size: model.sizes[app.id],
                tag: model.isSelectedAppExcluded ? "Dikecualiin" : nil, tagTint: .secondary,
                isSelected: model.includesApp, isEnabled: !model.isSelectedAppExcluded
            ) { model.includesApp.toggle() }

            if model.isLoadingLeftovers {
                Divider()
                HStack(spacing: Design.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Lagi nyari file sisa…").foregroundStyle(.secondary)
                }
                .padding(Design.Spacing.l)
            } else if model.leftovers.isEmpty {
                Divider()
                Text("Nggak ada file sisa yang ketemu.")
                    .foregroundStyle(.secondary)
                    .padding(Design.Spacing.l)
            } else {
                ForEach(model.leftovers) { leftover in
                    Divider()
                        .padding(.leading, Design.Spacing.l + Design.Column.checkbox + Design.Spacing.m)
                    ComponentRow(
                        title: leftover.kind.title, path: Format.path(leftover.url), size: leftover.size,
                        isSizeComplete: leftover.isFullyReadable,
                        tag: leftover.match == .appName ? "Cocok dari nama, cek dulu" : nil,
                        isSelected: model.leftoverSelection.contains(leftover.id)
                    ) { model.toggleLeftover(leftover) }
                    .contextMenu {
                        Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([leftover.url]) }
                        Divider()
                        Button("Masukin ke Pengecualian") { exclusions.add([leftover.url]) }
                    }
                }
            }
        }
        .card(padding: 0)
    }
}

private struct ComponentRow: View {
    let title: LocalizedStringKey
    let path: String
    let size: Int64?
    /// `false` when Havus couldn't read all of it, so `size` is only what it could read.
    var isSizeComplete = true
    var tag: LocalizedStringKey?
    var tagTint: Color = .orange
    let isSelected: Bool
    var isEnabled = true
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            SelectionBox(state: isSelected ? .on : .off, action: toggle)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(spacing: Design.Spacing.s) {
                    Text(title)
                        .font(Design.Typography.rowTitle)
                    if let tag {
                        Tag(text: tag, tint: tagTint)
                    }
                }
                Text(path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            Spacer(minLength: Design.Spacing.m)
            if let size {
                SizeText(bytes: size, isComplete: isSizeComplete)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Design.Spacing.l)
        .padding(.vertical, Design.Spacing.m)
        .selectableRow(isSelected ? .on : .off, toggle: toggle)
        .disabled(!isEnabled)
    }
}

private struct OutcomeView: View {
    let outcome: UninstallOutcome
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        if outcome.appBlocked {
            EmptyState(
                symbol: "exclamationmark.triangle", tint: .orange,
                title: Text("Belum berhasil"),
                message: Text(
                    "macOS nolak mindahin \(outcome.appName). Coba nyalain Havus di **Privacy & Security → App Management**, atau hapus manual lewat Finder."
                )
            ) {
                Button("Buka Pengaturan") { permissions.openAppManagementSettings() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            EmptyState(symbol: "checkmark", title: Text("Beres!"), message: message)
        }
    }

    private var message: Text {
        let bytes = Format.bytes(outcome.bytes)
        let summary =
            outcome.removedApp
            ? Text(
                "\(outcome.appName) dan \(outcome.removedLeftovers) file sisanya udah dipindah ke Tong Sampah (\(bytes))."
            )
            : Text("\(outcome.removedLeftovers) file sisa \(outcome.appName) udah dipindah ke Tong Sampah (\(bytes)).")
        guard outcome.failedCount > 0 else { return summary }
        return Text("\(summary) \(outcome.failedCount) item dilewati karena lagi dipakai atau butuh izin.")
    }
}

extension Leftover.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .applicationSupport: "Data aplikasi"
        case .caches: "Cache"
        case .preferences: "Preferensi"
        case .containers: "Container"
        case .groupContainers: "Group container"
        case .savedState: "Status jendela"
        case .logs: "Log"
        case .httpStorage: "Data HTTP"
        case .webKit: "Data WebKit"
        case .cookies: "Cookies"
        case .launchAgents: "Launch agent"
        case .applicationScripts: "Skrip aplikasi"
        }
    }
}
