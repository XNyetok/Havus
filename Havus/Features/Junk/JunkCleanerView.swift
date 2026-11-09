import HavusCore
import SwiftUI

struct JunkCleanerView: View {
    @Bindable var model: JunkCleanerModel
    let page: SidebarItem
    @State private var isConfirmingClean = false
    @State private var isConfirmingEmptyTrash = false
    /// Rules whose items are listed below them.
    @State private var expanded: Set<JunkRule.ID> = []

    var body: some View {
        PhaseContent(key: stateKey) {
            content
        }
        .toolbar {
            if model.phase != .idle {
                ToolbarItem(placement: .primaryAction) {
                    RescanButton { model.scan() }
                        .disabled(isBusy)
                }
            }
        }
        .confirmationDialog(
            Text("Bersihin \(model.selectedItems.count) item?"), isPresented: $isConfirmingClean,
            titleVisibility: .visible
        ) {
            Button("Bersihin \(Format.bytes(model.selectedSize))", role: .destructive) { model.clean() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text(
                model.selectionIncludesPermanentDeletion
                    ? "Isi Tong Sampah yang dipilih bakal dihapus permanen. Sisanya dipindah ke Tong Sampah, jadi masih bisa dibalikin."
                    : "Semuanya dipindah ke Tong Sampah, jadi masih bisa dibalikin kalau kamu berubah pikiran."
            )
        }
        .confirmationDialog("Kosongin Tong Sampah?", isPresented: $isConfirmingEmptyTrash, titleVisibility: .visible) {
            Button("Kosongin", role: .destructive) { model.emptyTrash() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Semua isi Tong Sampah bakal dihapus permanen dan nggak bisa dibalikin.")
        }
    }

    private var isBusy: Bool {
        switch model.phase {
        case .scanning, .cleaning: true
        default: false
        }
    }

    /// The state on screen, without its counters, so progress updates don't restart the crossfade.
    private var stateKey: String {
        switch model.phase {
        case .idle: "idle"
        case .scanning: "scanning"
        case .results: model.visibleResults.isEmpty ? "clean" : "results"
        case .cleaning: "cleaning"
        case .finished: "finished"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyState(
                symbol: page.symbol,
                title: Text(model.group == .system ? "Siap bersih-bersih?" : "Bersihin sisa ngoding?"),
                message: Text(
                    model.group == .system
                        ? "Havus bakal ngecek cache, log, dan file sisa yang aman dibuang. Kamu tetap bisa milih mana yang mau dihapus."
                        : "Havus bakal ngecek DerivedData Xcode, cache simulator, sampai cache npm, Homebrew, dan Cargo."
                )
            ) {
                Button("Pindai Sekarang") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

        case .scanning(let finished, let total):
            ScanProgress(
                symbol: page.symbol,
                title: Text("Lagi nyari sampah…"),
                fraction: Double(finished) / Double(max(total, 1)),
                detail: Text("Lokasi \(finished) dari \(total)"),
                cancel: { model.cancel() }
            )

        case .results where model.visibleResults.isEmpty:
            EmptyState(
                symbol: "checkmark.seal",
                title: Text("Bersih kinclong!"),
                message: Text("Nggak ada sampah yang ketemu di sini.")
            ) {
                Button("Pindai Lagi") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

        case .results:
            results

        case .cleaning:
            ScanProgress(symbol: page.symbol, title: Text("Lagi dibersihin…"))

        case .finished(let summary):
            FinishedView(
                summary: summary,
                onScanAgain: { model.scan() },
                onEmptyTrash: { isConfirmingEmptyTrash = true })
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            RowList {
                SummaryHeader {
                    RollingSize(bytes: model.totalSize)
                } caption: {
                    Text("bisa dibersihin")
                } notes: {
                    LockedNotice(count: model.visibleResults.filter { $0.status == .noPermission }.count)
                }
            } content: {
                ForEach(Array(model.visibleResults.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        RowDivider(inset: Design.Column.checkbox + Design.Spacing.m)
                    }
                    JunkResultRow(result: result, model: model, isExpanded: isExpanded(result.id))
                }
            }
            ActionBar {
                Text("\(model.selection.count) item dipilih · \(Format.bytes(model.selectedSize))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Design.Motion.quick, value: model.selectedSize)
            } trailing: {
                Button("Bersihin") { isConfirmingClean = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selection.isEmpty)
            }
        }
    }

    private func isExpanded(_ id: JunkRule.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            })
    }
}

/// One banner for every location macOS kept Havus out of, instead of a button on each of their rows.
private struct LockedNotice: View {
    let count: Int
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        if count > 0 {
            NoticeBanner(
                tone: .warning, symbol: "lock.fill",
                message: Text("\(count) lokasi butuh Akses Disk Penuh buat dicek.")
            ) {
                Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
            }
        }
    }
}

/// A rule's row: everything it found in one line, and its items below when it's opened.
private struct JunkResultRow: View {
    let result: JunkScanResult
    let model: JunkCleanerModel
    @Binding var isExpanded: Bool

    var body: some View {
        if result.status == .noPermission {
            LockedRow(rule: result.rule)
        } else if result.rule.strategy == .wholeContents, let item = result.items.first {
            let state: CheckState = model.selection.contains(item.id) ? .on : .off
            header(state: state, canExpand: false) { model.toggle(item) }
                .selectableRow(state) { model.toggle(item) }
        } else {
            let state = model.selectionState(of: result)
            header(state: state, canExpand: true) { model.toggleAll(in: result) }
                .rowHighlight()
                .onTapGesture { toggleExpanded() }
                .selectableGroupLabel(state) { model.toggleAll(in: result) }
                .accessibilityAction { toggleExpanded() }
                .accessibilityHint(isExpanded ? "Tutup daftarnya" : "Buka daftarnya")
            if isExpanded {
                ForEach(result.items) { item in
                    JunkItemRow(item: item, isSelected: model.selection.contains(item.id)) { model.toggle(item) }
                        .transition(.opacity)
                }
                .padding(.bottom, Design.Spacing.s)
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(Design.Motion.quick) { isExpanded.toggle() }
    }

    private func header(state: CheckState, canExpand: Bool, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: Design.Spacing.m) {
            SelectionBox(state: state, action: toggle)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(spacing: Design.Spacing.s) {
                    Text(result.rule.id.title)
                        .font(Design.Typography.rowTitle)
                    if result.rule.removal == .deletePermanently {
                        Tag(text: "Permanen", tint: .red)
                    } else if result.rule.safety == .review {
                        Tag(text: "Cek dulu", tint: .orange)
                    }
                }
                Text(result.rule.id.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Design.Spacing.m)
            Text(Format.bytes(result.totalSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: Design.Column.size, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: Design.Column.chevron)
                .opacity(canExpand ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Design.Spacing.m)
    }
}

/// One item of a rule, under its row when the row is opened. Lines up with the row's name.
private struct JunkItemRow: View {
    let item: JunkItem
    let isSelected: Bool
    let toggle: () -> Void
    @Environment(ExclusionStore.self) private var exclusions

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            SelectionBox(state: isSelected ? .on : .off, action: toggle)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(Format.path(item.url))
            if item.isInUse {
                Tag(text: "Lagi dipakai")
            }
            Spacer(minLength: Design.Spacing.m)
            Text(Format.bytes(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: Design.Column.size, alignment: .trailing)
            Color.clear
                .frame(width: Design.Column.chevron, height: 1)
        }
        .font(.callout)
        .padding(.leading, Design.Column.checkbox + Design.Spacing.m)
        .padding(.vertical, Design.Spacing.xs)
        .selectableRow(isSelected ? .on : .off, toggle: toggle)
        .contextMenu {
            Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Masukin ke Pengecualian") { exclusions.add([item.url]) }
        }
    }
}

/// A location macOS kept Havus out of. The banner above the list has the button to the setting.
private struct LockedRow: View {
    let rule: JunkRule

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: Design.Column.checkbox)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(rule.id.title)
                    .font(Design.Typography.rowTitle)
                    .foregroundStyle(.secondary)
                Text("Butuh Akses Disk Penuh buat ngecek lokasi ini.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Design.Spacing.m)
        }
        .padding(.vertical, Design.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

private struct FinishedView: View {
    let summary: CleanupSummary
    let onScanAgain: () -> Void
    let onEmptyTrash: () -> Void
    @State private var hasAppeared = false

    /// Every item failed, so nothing was cleaned up.
    private var failedEntirely: Bool {
        summary.failedCount > 0 && summary.trashedBytes == 0 && summary.deletedBytes == 0
    }

    var body: some View {
        VStack(spacing: Design.Spacing.m) {
            SymbolDisc(
                symbol: symbol,
                tint: summary.trashNeedsPermission || failedEntirely ? .orange : .accentColor
            )
            .symbolEffect(.bounce, value: hasAppeared)
            .padding(.bottom, Design.Spacing.xs)
            title
                .font(.title2.weight(.semibold))
            VStack(spacing: Design.Spacing.xs) {
                if summary.trashNeedsPermission {
                    Text("Buat ngosongin Tong Sampah, Havus butuh Akses Disk Penuh. Atau kosongin manual lewat Finder.")
                }
                if summary.trashedBytes > 0 {
                    Text(
                        "\(Format.bytes(summary.trashedBytes)) udah dipindah ke Tong Sampah. Kosongin Tong Sampah biar ruangnya beneran lega."
                    )
                }
                if summary.deletedBytes > 0 {
                    Text("\(Format.bytes(summary.deletedBytes)) udah dihapus permanen.")
                }
                if failedEntirely {
                    Text("\(summary.failedCount) item nggak bisa dibersihin karena lagi dipakai atau butuh izin.")
                } else if summary.failedCount > 0 {
                    Text("\(summary.failedCount) item dilewati karena lagi dipakai atau butuh izin.")
                }
                if summary == CleanupSummary() {
                    Text("Nggak ada yang perlu dibersihin.")
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Design.messageWidth)
            HStack(spacing: Design.Spacing.s) {
                if summary.trashedBytes > 0 {
                    Button("Kosongin Tong Sampah", action: onEmptyTrash)
                }
                Button("Pindai Lagi", action: onScanAgain)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, Design.Spacing.s)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
    }

    private var symbol: String {
        if summary.trashNeedsPermission { return "lock.shield" }
        return failedEntirely ? "exclamationmark.triangle" : "checkmark"
    }

    private var title: Text {
        if summary.trashNeedsPermission { return Text("Butuh izin dulu") }
        return failedEntirely ? Text("Belum berhasil") : Text("Beres!")
    }
}
