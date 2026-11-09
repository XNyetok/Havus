import AppKit
import HavusCore
import SwiftUI

struct StartupItemsView: View {
    @Bindable var model: StartupItemsModel
    /// Shows an app in Hapus Aplikasi: removing the app is the lasting fix for an agent it keeps writing again.
    let openInUninstaller: (InstalledApp) -> Void
    @Environment(ExclusionStore.self) private var exclusions
    @State private var pendingRemoval: LaunchAgent?

    var body: some View {
        VStack(spacing: 0) {
            PhaseContent(key: stateKey) {
                content
            }
            ActionBar {
                Text("Item lain, kayak aplikasi yang kebuka pas login, diatur di Pengaturan Sistem.")
                    .foregroundStyle(.secondary)
            } trailing: {
                Button("Buka Item Masuk") { model.openLoginItemsSettings() }
            }
        }
        .toolbar {
            if model.hasLoaded {
                ToolbarItem(placement: .primaryAction) {
                    RescanButton { model.rescan() }
                }
            }
        }
        .task { model.refresh() }
        // The user may have changed something in System Settings or Terminal in the meantime.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible, presenting: pendingRemoval
        ) { agent in
            Button("Pindahin ke Tong Sampah", role: .destructive) { model.remove(agent) }
            if model.status(of: agent) == .on {
                Button("Matiin Aja") { model.setOn(false, for: agent) }
            }
            Button("Batal", role: .cancel) {}
        } message: { agent in
            removalMessage(for: agent)
        }
        .alert(
            problemTitle,
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }),
            presenting: model.problem
        ) { _ in
            Button("Oke", role: .cancel) {}
        } message: { problem in
            problemMessage(problem)
        }
    }

    private var stateKey: String {
        if !model.hasLoaded { return "loading" }
        return model.agents.isEmpty ? "empty" : "list"
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ScanProgress(symbol: SidebarItem.startupItems.symbol, title: Text("Lagi ngecek yang jalan otomatis…"))
        } else if model.agents.isEmpty {
            EmptyState(
                symbol: "checkmark.seal", title: Text("Nggak ada launch agent"),
                message: Text("Belum ada aplikasi yang masang launch agent di akun kamu."))
        } else {
            list
        }
    }

    private var list: some View {
        RowList {
            SummaryHeader {
                Text("\(model.agents.count) launch agent")
            } caption: {
                Text("di akun kamu")
            } notes: {
                if let file = model.lastRemoval {
                    NoticeBanner(
                        tone: .success, symbol: "checkmark",
                        message: Text("\(file) udah dipindah ke Tong Sampah."))
                }
            }
        } content: {
            ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, agent in
                if index > 0 {
                    RowDivider(inset: Design.Column.icon + Design.Spacing.m)
                }
                StartupItemRow(
                    agent: agent, status: model.status(of: agent), isRunning: model.isRunning(agent),
                    isOn: model.isOn(agent), isChanging: model.pendingChanges[agent.id] != nil,
                    setOn: { model.setOn($0, for: agent) }
                ) {
                    actions(for: agent)
                }
                .contextMenu { actions(for: agent) }
            }
            Text(
                "Mending dimatiin aja. Banyak aplikasi bikin lagi agent-nya kalau file-nya dihapus, sedangkan agent yang dimatiin biasanya tetap mati. Biar beres, hapus aplikasinya lewat **Hapus Aplikasi**."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: Design.paragraphWidth, alignment: .leading)
            .padding(.top, Design.Spacing.l)
        }
    }

    /// In the row's menu and in its right-click menu.
    @ViewBuilder
    private func actions(for agent: LaunchAgent) -> some View {
        Button("Tampilkan di Finder") { model.reveal(agent) }
        if let app = agent.owner?.installedApp {
            Button("Buka \(app.name) di Hapus Aplikasi") { openInUninstaller(app) }
        }
        Divider()
        Button("Pindahin ke Tong Sampah…") { pendingRemoval = agent }
        Button("Masukin ke Pengecualian") { exclusions.add([agent.url]) }
    }

    // MARK: - Removing

    private var removalTitle: Text {
        Text("Pindahin \(pendingRemoval?.url.lastPathComponent ?? "") ke Tong Sampah?")
    }

    private func removalMessage(for agent: LaunchAgent) -> Text {
        guard let job = agent.job else {
            return Text("File ini kosong atau rusak, jadi macOS nggak pernah ngejalaninnya. Aman dibuang.")
        }
        if job.isProgramMissing {
            return Text("Programnya udah nggak ada, jadi agent ini nggak bisa jalan lagi. Aman dibuang.")
        }
        if let app = agent.owner?.installedApp {
            return Text(
                "\(app.name) bisa bikin lagi agent ini waktu dibuka. Biar beres, hapus \(app.name) lewat Hapus Aplikasi."
            )
        }
        if let owner = agent.owner {
            return Text("\(owner.name) bisa bikin lagi agent ini. Kalau cuma mau agent ini berhenti, matiin aja.")
        }
        return Text("Kalau ternyata masih butuh, kamu bisa balikin file-nya dari Tong Sampah.")
    }

    // MARK: - Problems

    private var problemTitle: Text {
        switch model.problem {
        case .turnOff(let name, _): Text("Havus nggak bisa matiin \(name)")
        case .turnOn(let name, _): Text("Havus nggak bisa nyalain \(name)")
        case .remove(let file, _): Text("Havus nggak bisa mindahin \(file) ke Tong Sampah")
        case nil: Text(verbatim: "")
        }
    }

    private func problemMessage(_ problem: StartupItemsProblem) -> Text {
        switch problem {
        case .turnOff(_, let message), .turnOn(_, let message):
            Text("Kata launchctl: \(message)")
        case .remove(_, .blocked(.excluded)):
            Text("File ini ada di daftar Pengecualian.")
        case .remove(_, .blocked):
            Text("Havus nggak boleh nyentuh file di lokasi ini.")
        case .remove(_, .notFound):
            Text("File-nya udah nggak ada.")
        case .remove(_, .other(let message)):
            Text(verbatim: message)
        case .remove(_, .permissionDenied), .remove(_, nil):
            Text("macOS nggak ngizinin Havus mindahin file ini.")
        }
    }
}

private struct StartupItemRow<Actions: View>: View {
    let agent: LaunchAgent
    let status: LaunchAgent.Status
    let isRunning: Bool
    let isOn: Bool
    let isChanging: Bool
    let setOn: @MainActor (Bool) -> Void
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            FileIcon(url: agent.owner?.url ?? agent.url)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(spacing: Design.Spacing.s) {
                    Text(verbatim: agent.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    tag
                }
                details
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .help(locations)
            Spacer(minLength: Design.Spacing.m)
            state
                .font(.callout)
                .foregroundStyle(.secondary)
            if agent.job != nil {
                Toggle(isOn: Binding(get: { isOn }, set: { setOn($0) })) {
                    Text(verbatim: agent.name)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(isChanging || status == .offInSystemSettings)
                .help(toggleHelp)
            }
            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Pilihan lain buat \(agent.name)"))
        }
        .padding(.vertical, Design.Spacing.s)
    }

    @ViewBuilder
    private var tag: some View {
        if agent.job == nil {
            Tag(text: "Nggak kepakai")
        } else if agent.job?.isProgramMissing == true {
            Tag(text: "Programnya udah nggak ada", tint: .orange)
                .help("Program yang mau dijalanin udah dihapus, jadi agent ini cuma gagal tiap kali dicoba.")
        }
    }

    /// "Tiap login · com.example.agent". Without a known app, the program says more than the label.
    private var details: Text {
        guard let job = agent.job else {
            return Text("File-nya kosong atau rusak, jadi nggak pernah dijalanin macOS.")
        }
        let what = agent.owner != nil ? job.label : job.program.map(Format.path) ?? job.label
        return Text(verbatim: "\(job.schedule.title) · \(what)")
    }

    /// The program and the file, in full, for the tooltip.
    private var locations: String {
        [agent.job?.program.map(Format.path), Format.path(agent.url)].compactMap { $0 }.joined(separator: "\n")
    }

    @ViewBuilder
    private var state: some View {
        if status == .on, isRunning {
            Label {
                Text("Lagi jalan")
            } icon: {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            }
        } else if isRunning, status != .invalid {
            Text("Masih jalan")
                .help("Udah dimatiin, tapi programnya baru berhenti setelah kamu logout.")
        } else if status == .offInSystemSettings {
            Text("Dimatiin di Pengaturan Sistem")
        }
    }

    private var toggleHelp: LocalizedStringKey {
        switch status {
        case .offInSystemSettings:
            "Kamu cuma bisa nyalain lagi di Pengaturan Sistem, lewat Umum → Item Masuk & Ekstensi."
        case .on: "Matiin biar nggak jalan otomatis lagi"
        default: "Nyalain biar jalan otomatis lagi"
        }
    }
}

extension LaunchAgent.Schedule {
    /// "Tiap login", "Tiap 1 jam", …
    var title: String {
        switch self {
        case .alwaysRunning: String(localized: "Selalu jalan")
        case .atLogin: String(localized: "Tiap login")
        case .interval(let seconds): String(localized: "Tiap \(Format.duration(seconds: seconds))")
        case .calendar: String(localized: "Terjadwal")
        case .onDemand: String(localized: "Kalau dibutuhin")
        }
    }
}
