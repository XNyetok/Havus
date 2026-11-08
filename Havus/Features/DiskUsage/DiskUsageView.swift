import HavusCore
import SwiftUI

/// "Peta Disk": the folders and files in the home folder, biggest first, each with a bar for its share of the
/// folder on screen. Click a folder to see inside it. Read-only.
struct DiskUsageView: View {
    let model: DiskUsageModel

    var body: some View {
        PhaseContent(key: stateKey) {
            content
        }
        .toolbar {
            if model.phase == .results {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.goUp()
                    } label: {
                        Label("Balik", systemImage: "chevron.left")
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Balik ke folder di atasnya")
                    .disabled(model.path.count < 2)
                }
            }
            if model.phase != .idle {
                ToolbarItem(placement: .primaryAction) {
                    RescanButton { model.scan() }
                        .disabled(model.phase == .scanning)
                }
            }
        }
    }

    private var stateKey: String {
        switch model.phase {
        case .idle: "idle"
        case .scanning: "scanning"
        case .results: "results"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyState(
                symbol: SidebarItem.diskUsage.symbol,
                title: Text("Lihat ke mana ruang disk kamu"),
                message: Text(
                    "Havus ngitung ukuran tiap folder di folder home kamu, termasuk yang tersembunyi. Cuma dilihat, nggak ada yang dihapus."
                )
            ) {
                Button("Pindai Sekarang") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

        case .scanning:
            ScanProgress(
                symbol: SidebarItem.diskUsage.symbol,
                title: Text("Lagi ngitung ukuran folder…"),
                detail: model.progress.map { Text("\(Format.bytes($0.bytes)) udah dihitung") },
                cancel: { model.cancel() }
            )

        case .results:
            if let folder = model.current {
                results(folder)
            }
        }
    }

    // Nothing outside the list may use `fixedSize(horizontal: false, vertical: true)`. The page's minimum height is
    // measured with its text squeezed narrow, where such a text grows hundreds of points tall. The window doesn't grow
    // along, so the whole page, sidebar included, gets laid out taller than the window and is cut off at both ends.
    private func results(_ folder: DiskUsageItem) -> some View {
        ZStack {
            RowList {
                FolderSummary(folder: folder, path: model.path) { model.goBack(to: $0) }
            } content: {
                contents(of: folder)
                Text(
                    "Di sini cuma dilihat, nggak ada yang dihapus. Buat bersihin, pakai **Sampah Sistem**, **Sampah Developer**, atau **File Gede & Lama**."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: Design.paragraphWidth, alignment: .leading)
                .padding(.top, Design.Spacing.l)
            }
            // A new folder starts at the top of the list, and fades in.
            .id(folder.id)
            .transition(.opacity)
        }
        .animation(Design.Motion.quick, value: folder.id)
    }

    @ViewBuilder
    private func contents(of folder: DiskUsageItem) -> some View {
        let children = folder.children ?? []
        if children.isEmpty, folder.otherItems.count == 0 {
            Group {
                if folder.isComplete {
                    Text("Folder ini kosong.")
                } else {
                    Text("macOS nggak ngizinin Havus baca isi folder ini.")
                }
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, Design.Spacing.m)
        } else {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    RowDivider(inset: Design.Column.icon + Design.Spacing.m)
                }
                row(item, share: share(item.bytes, of: folder))
            }
            if folder.otherItems.count > 0 {
                RowDivider(inset: Design.Column.icon + Design.Spacing.m)
                OtherItemsRow(other: folder.otherItems, share: share(folder.otherItems.bytes, of: folder))
            }
        }
    }

    @ViewBuilder
    private func row(_ item: DiskUsageItem, share: Double) -> some View {
        let isExcluded = model.isExcluded(item)
        let row = DiskUsageRow(item: item, share: share, isExcluded: isExcluded, isOpening: model.opening == item.id)
        // Named on the element VoiceOver lands on. Combining the row's children left it without a name: VoiceOver said
        // only the share, such as "79%, button".
        Group {
            if item.kind == .folder {
                Button {
                    model.open(item)
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .rowHighlight()
                .accessibilityLabel(spokenName(of: item, isExcluded: isExcluded))
                .accessibilityValue(Format.percent(share))
                .accessibilityHint("Buka folder ini")
            } else {
                row
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel(spokenName(of: item, isExcluded: isExcluded))
                    .accessibilityValue(Format.percent(share))
            }
        }
        .contextMenu {
            if item.kind == .folder {
                Button("Buka") { model.open(item) }
            }
            Button("Tampilkan di Finder") { model.reveal(item) }
        }
    }

    private func share(_ bytes: Int64, of folder: DiskUsageItem) -> Double {
        folder.bytes > 0 ? Double(bytes) / Double(folder.bytes) : 0
    }

    /// The name, the size and whether it's excluded, e.g. "Library, More than 15.92 GB". The share follows as the value.
    private func spokenName(of item: DiskUsageItem, isExcluded: Bool) -> Text {
        var parts = [item.name, SizeText.spoken(bytes: item.bytes, isComplete: item.isComplete)]
        if isExcluded { parts.append(String(localized: "Dikecualiin")) }
        return Text(verbatim: parts.joined(separator: ", "))
    }
}

/// Where the user is and how big the folder on screen is, above its list. Built like ``SummaryHeader``, with the way
/// back above the size.
private struct FolderSummary: View {
    let folder: DiskUsageItem
    let path: [DiskUsageItem]
    let goTo: (Int) -> Void
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Breadcrumb(path: path, goTo: goTo)
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                RollingSize(bytes: folder.bytes, isComplete: folder.isComplete)
                    .font(Design.Typography.metric)
                    .monospacedDigit()
                Text("di folder ini")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            // While the folder on screen has parts macOS keeps closed without Full Disk Access, its size is too low.
            if !folder.isComplete, !permissions.hasFullDiskAccess {
                NoticeBanner(
                    tone: .warning, symbol: "lock.fill",
                    message: Text(
                        "Sebagian isi folder ini nggak bisa dibaca Havus, jadi ukurannya belum lengkap. Nyalain Akses Disk Penuh, terus pindai ulang."
                    )
                ) {
                    Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                }
                .padding(.top, Design.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.pageMargin)
        .padding(.top, Design.Spacing.l)
        .padding(.bottom, Design.Spacing.m)
    }
}

/// The folders from the home folder down to the one on screen. Leaves out the middle ones when they don't fit.
private struct Breadcrumb: View {
    let path: [DiskUsageItem]
    let goTo: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            crumbs(path.indices.map { $0 })
            if path.count > 3 {
                crumbs([0, nil] + path.indices.suffix(2).map { $0 })
            }
            // The folder on screen alone, shortened in the middle when even that doesn't fit, so a long name never
            // makes the page wider than the window.
            title(path.count - 1)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    /// `nil` stands for the folders left out.
    private func crumbs(_ indices: [Int?]) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(Array(indices.enumerated()), id: \.offset) { position, index in
                if position > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let index {
                    crumb(index)
                } else {
                    Text(verbatim: "…")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func crumb(_ index: Int) -> some View {
        if index == path.count - 1 {
            title(index)
        } else {
            Button {
                goTo(index)
            } label: {
                label(index)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    /// The folder on screen.
    private func title(_ index: Int) -> some View {
        label(index)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    /// The home folder gets a house in front of its name.
    private func label(_ index: Int) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            if index == 0 {
                Image(systemName: "house")
                    .accessibilityHidden(true)
            }
            Text(path[index].name)
        }
    }
}

private struct DiskUsageRow: View {
    let item: DiskUsageItem
    let share: Double
    let isExcluded: Bool
    let isOpening: Bool

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            FileIcon(url: item.url)
            HStack(spacing: Design.Spacing.s) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isExcluded {
                    Tag(text: "Dikecualiin")
                }
            }
            Spacer(minLength: Design.Spacing.m)
            ShareBar(share: share)
                .frame(width: 120)
            SizeText(bytes: item.bytes, isComplete: item.isComplete)
                .monospacedDigit()
                .frame(minWidth: Design.Column.size, alignment: .trailing)
            disclosure
                .frame(width: Design.Column.chevron)
        }
        .padding(.vertical, Design.Spacing.s)
        .contentShape(Rectangle())
        .help(Format.path(item.url))
    }

    @ViewBuilder
    private var disclosure: some View {
        if isOpening {
            ProgressView()
                .controlSize(.small)
        } else if item.kind == .folder {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

/// The smaller items of a folder, added up in one row so the list stays short.
private struct OtherItemsRow: View {
    let other: DiskUsageItem.OtherItems
    let share: Double

    var body: some View {
        HStack(spacing: Design.Spacing.m) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: Design.Column.icon, height: Design.Column.icon)
                .accessibilityHidden(true)
            Text("\(other.count) item lain")
                .foregroundStyle(.secondary)
            Spacer(minLength: Design.Spacing.m)
            ShareBar(share: share, tint: .secondary)
                .frame(width: 120)
            Text(Format.bytes(other.bytes))
                .monospacedDigit()
                .frame(minWidth: Design.Column.size, alignment: .trailing)
            Color.clear
                .frame(width: Design.Column.chevron, height: 1)
        }
        .padding(.vertical, Design.Spacing.s)
        .help("Item yang lebih kecil, digabung biar daftarnya nggak kepanjangan.")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(
            Text(verbatim: "\(String(localized: "\(other.count) item lain")), \(Format.bytes(other.bytes))")
        )
        .accessibilityValue(Format.percent(share))
    }
}

/// An item's share of the folder on screen: a thin bar on a lighter track of the same hue, square where it starts
/// and rounded where it ends. The size next to it carries the number, so the bar needs no label.
private struct ShareBar: View {
    let share: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                bar.fill(tint.opacity(0.15))
                if share > 0 {
                    // Never thinner than 2 points, so a tiny share still shows up.
                    bar.fill(tint)
                        .frame(width: max(2, geometry.size.width * min(share, 1)))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var bar: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 4, topTrailing: 4), style: .continuous)
    }
}
