import HavusCore
import QuickLook
import SwiftUI

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    @Environment(PermissionCenter.self) private var permissions
    @State private var isConfirming = false

    var body: some View {
        PhaseContent(key: stateKey) {
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Ukuran minimal", selection: $model.minimumSize) {
                    ForEach(LargeFilesModel.MinimumSize.allCases) { size in
                        Text("Minimal \(size.label)").tag(size)
                    }
                }
                .help("Ukuran minimal")
                .disabled(model.phase == .removing)
                Picker("Terakhir dibuka", selection: $model.lastOpened) {
                    ForEach(LargeFilesModel.LastOpened.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .help("Terakhir dibuka")
                .disabled(model.phase == .removing)
                if model.phase != .idle {
                    RescanButton(title: "Cari Ulang") { model.search() }
                        .disabled(model.phase == .searching || model.phase == .removing)
                }
            }
        }
        .onChange(of: model.minimumSize) { model.filtersChanged() }
        .onChange(of: model.lastOpened) { model.filtersChanged() }
        .confirmationDialog(
            Text("Pindahin \(model.selectedFiles.count) file ke Tong Sampah?"), isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Pindahin \(Format.bytes(model.selectedSize))", role: .destructive) { model.moveSelectionToTrash() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("File masih bisa dibalikin dari Tong Sampah sampai kamu ngosonginnya.")
        }
    }

    /// The state on screen. Removing keeps the list, so it's the same state as results.
    private var stateKey: String {
        switch model.phase {
        case .idle: "idle"
        case .searching: "searching"
        case .results, .removing: model.files.isEmpty ? "none" : "results"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyState(
                symbol: SidebarItem.largeFiles.symbol,
                title: Text("Cari file yang makan tempat"),
                message: Text(
                    "Havus pakai index Spotlight buat nyari file gede di folder kamu (di luar Library). Nggak ada yang dihapus tanpa persetujuan kamu."
                ),
                note: permissions.hasFullDiskAccess ? nil : FullDiskAccessNote.text
            ) {
                if permissions.hasFullDiskAccess {
                    Button("Cari Sekarang") { model.search() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cari Aja") { model.search() }
                    Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

        case .searching:
            ScanProgress(
                symbol: SidebarItem.largeFiles.symbol,
                title: Text("Lagi nyari file gede…"),
                cancel: { model.cancel() }
            )

        case .results, .removing:
            if model.files.isEmpty {
                EmptyState(
                    symbol: "checkmark.seal", title: Text("Nggak ada yang cocok"),
                    message: Text("Coba turunin ukuran minimal, atau cari juga file yang masih sering dibuka."))
            } else {
                results
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            LargeFileList(model: model)
            ActionBar {
                Text("\(model.selection.count) file dipilih · \(Format.bytes(model.selectedSize))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Design.Motion.quick, value: model.selectedSize)
            } trailing: {
                Button("Pindahin ke Tong Sampah") { isConfirming = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.selection.isEmpty || model.phase == .removing)
            }
        }
    }
}

/// The files found, with Quick Look: a click picks a row, Space shows the file, and the arrow keys move to the next
/// one, like in Finder. The checkbox stays the only way to pick files for the Trash.
private struct LargeFileList: View {
    let model: LargeFilesModel
    @Environment(ExclusionStore.self) private var exclusions
    @Environment(PermissionCenter.self) private var permissions
    /// The row a click or the arrow keys picked, which Space shows.
    @State private var highlighted: LargeFile.ID?
    /// The file Quick Look shows, if it's open.
    @State private var previewURL: URL?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            RowList {
                SummaryHeader {
                    RollingSize(bytes: model.totalSize)
                } caption: {
                    Text("di \(model.files.count) file")
                } notes: {
                    if let removal = model.lastRemoval {
                        RemovalNotice(removal: removal)
                    }
                    if model.skippedMediaLibraries, !permissions.hasFullDiskAccess {
                        NoticeBanner(
                            tone: .warning, symbol: "lock.fill",
                            message: Text(
                                "Pustaka Foto dan Musik nggak ikut dicari, karena Akses Disk Penuh belum nyala.")
                        ) {
                            Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                        }
                    }
                    Label("Klik sebuah file, lalu tekan Spasi buat lihat isinya.", systemImage: "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } content: {
                ForEach(Array(model.files.enumerated()), id: \.element.id) { index, file in
                    if index > 0 {
                        RowDivider(inset: Design.Column.checkbox + Design.Column.icon + 2 * Design.Spacing.m)
                    }
                    LargeFileRow(file: file, isSelected: model.selection.contains(file.id)) { model.toggle(file) }
                        .rowHighlight(highlighted == file.id)
                        .onTapGesture {
                            highlighted = file.id
                            isFocused = true
                        }
                        .accessibilityAction(named: "Lihat Sekilas") { preview(file) }
                        .contextMenu {
                            Button("Lihat Sekilas") { preview(file) }
                            Button("Tampilkan di Finder") { model.reveal(file) }
                            Button("Buka") { model.open(file) }
                            Divider()
                            Button("Masukin ke Pengecualian") { exclusions.add([file.url]) }
                        }
                        .id(file.id)
                }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard let file = highlightedFile ?? model.files.first else { return .ignored }
                preview(file)
                return .handled
            }
            .onKeyPress(.downArrow) { move(by: 1, proxy: proxy) }
            .onKeyPress(.upArrow) { move(by: -1, proxy: proxy) }
        }
        .quickLookPreview($previewURL, in: model.files.map(\.url))
        // Quick Look's own arrow keys go through the list too, and the highlight follows.
        .onChange(of: previewURL) { _, url in
            if let url, let file = model.files.first(where: { $0.url == url }) {
                highlighted = file.id
            }
        }
    }

    private var highlightedFile: LargeFile? {
        model.files.first { $0.id == highlighted }
    }

    private func preview(_ file: LargeFile) {
        highlighted = file.id
        previewURL = file.url
    }

    private func move(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !model.files.isEmpty else { return .ignored }
        let current = model.files.firstIndex { $0.id == highlighted }
        let next = current.map { min(max($0 + offset, 0), model.files.count - 1) } ?? 0
        let id = model.files[next].id
        highlighted = id
        withAnimation(Design.Motion.quick) { proxy.scrollTo(id) }
        return .handled
    }
}

/// What the last move to the Trash did, above the list.
private struct RemovalNotice: View {
    let removal: RemovalSummary

    var body: some View {
        if removal.failedCount > 0 {
            NoticeBanner(
                tone: .warning, symbol: "exclamationmark.triangle.fill",
                message: Text(
                    "\(removal.count) file (\(Format.bytes(removal.bytes))) dipindah ke Tong Sampah, \(removal.failedCount) gagal."
                ))
        } else {
            NoticeBanner(
                tone: .success, symbol: "checkmark",
                message: Text("\(removal.count) file (\(Format.bytes(removal.bytes))) udah dipindah ke Tong Sampah."))
        }
    }
}

private struct LargeFileRow: View {
    let file: LargeFile
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            SelectionBox(state: isSelected ? .on : .off, action: toggle)
            FileIcon(url: file.url)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Format.path(file.url.deletingLastPathComponent()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Design.Spacing.m)
            lastUsed
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Format.bytes(file.size))
                .monospacedDigit()
                .frame(minWidth: Design.Column.size, alignment: .trailing)
        }
        .padding(.vertical, Design.Spacing.s)
        .selectableRow(isSelected ? .on : .off, toggle: toggle)
    }

    private var lastUsed: Text {
        if let date = file.lastOpened {
            Text("Dibuka \(Format.relativeDate(date))")
        } else if let date = file.modified {
            Text("Diubah \(Format.relativeDate(date))")
        } else {
            Text(verbatim: "–")
        }
    }
}

extension LargeFilesModel.LastOpened {
    /// Shown in the toolbar, so it says what the filter keeps.
    var label: LocalizedStringKey {
        switch self {
        case .any: "Dibuka kapan aja"
        case .threeMonths: "Nggak dibuka 3 bulan"
        case .sixMonths: "Nggak dibuka 6 bulan"
        case .oneYear: "Nggak dibuka setahun"
        }
    }
}
