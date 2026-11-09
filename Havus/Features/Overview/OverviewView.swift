import HavusCore
import SwiftUI

/// The models of the other pages, so Ringkasan can show where each one stands.
struct OverviewTools {
    let systemJunk: JunkCleanerModel
    let developerJunk: JunkCleanerModel
    let uninstaller: UninstallerModel
    let largeFiles: LargeFilesModel
    let diskUsage: DiskUsageModel
    let startupItems: StartupItemsModel
}

struct OverviewView: View {
    let tools: OverviewTools
    let open: (SidebarItem) -> Void
    @State private var disk: DiskSpace?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                UpdateBanner()
                if let disk {
                    DiskHero(disk: disk, systemJunk: tools.systemJunk, developerJunk: tools.developerJunk) {
                        open(.diskUsage)
                    }
                }
                FullDiskAccessBanner()
                // Always 3×2, so the six tools stay balanced at any window width.
                Grid(horizontalSpacing: Design.Spacing.m, verticalSpacing: Design.Spacing.m) {
                    GridRow {
                        tile(.systemJunk)
                        tile(.developerJunk)
                        tile(.uninstaller)
                    }
                    GridRow {
                        tile(.largeFiles)
                        tile(.diskUsage)
                        tile(.startupItems)
                    }
                }
                Label("Semua proses jalan di Mac kamu. Havus nggak ngirim data kamu ke internet.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Design.pageMargin)
            .frame(maxWidth: Design.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { disk = try? DiskSpace.startupDisk() }
    }

    private func tile(_ item: SidebarItem) -> some View {
        ToolTile(item: item, status: status(of: item)) { open(item) }
    }

    /// Where a tool stands, in a few words under its tile. `nil` while there's nothing to say yet.
    private func status(of item: SidebarItem) -> ToolStatus? {
        switch item {
        case .systemJunk: junkStatus(tools.systemJunk)
        case .developerJunk: junkStatus(tools.developerJunk)
        case .uninstaller:
            tools.uninstaller.apps.isEmpty ? nil : .info(Text("\(tools.uninstaller.apps.count) aplikasi"))
        case .largeFiles: largeFilesStatus
        case .diskUsage: diskUsageStatus
        case .startupItems:
            tools.startupItems.hasLoaded
                ? .info(Text("\(tools.startupItems.agents.count) launch agent")) : nil
        case .overview, .about: nil
        }
    }

    private func junkStatus(_ model: JunkCleanerModel) -> ToolStatus {
        switch model.phase {
        case .idle: .pending(Text("Belum dipindai"))
        case .scanning: .busy(Text("Lagi dipindai…"))
        case .results:
            model.totalSize > 0
                ? .found(Text("\(Format.bytes(model.totalSize)) bisa dibersihin")) : .info(Text("Bersih kinclong!"))
        case .cleaning: .busy(Text("Lagi dibersihin…"))
        case .finished: .info(Text("Beres!"))
        }
    }

    private var largeFilesStatus: ToolStatus? {
        let model = tools.largeFiles
        switch model.phase {
        case .idle: return nil
        case .searching: return .busy(Text("Lagi nyari file gede…"))
        case .results, .removing:
            return model.files.isEmpty
                ? .info(Text("Nggak ada yang cocok")) : .found(Text("\(Format.bytes(model.totalSize)) ketemu"))
        }
    }

    private var diskUsageStatus: ToolStatus? {
        let model = tools.diskUsage
        switch model.phase {
        case .idle: return nil
        case .scanning: return .busy(Text("Lagi ngitung ukuran folder…"))
        case .results:
            guard let root = model.root else { return nil }
            return .info(Text("\(Format.bytes(root.bytes)) di folder home"))
        }
    }
}

/// The state line under a tool's tile.
private enum ToolStatus {
    /// Not run yet.
    case pending(Text)
    /// Working on it.
    case busy(Text)
    /// Found something to clean up.
    case found(Text)
    /// Anything else worth knowing.
    case info(Text)
}

/// The startup disk: how much room is left, a ring for how full it is, and the button that scans both junk pages.
private struct DiskHero: View {
    let disk: DiskSpace
    let systemJunk: JunkCleanerModel
    let developerJunk: JunkCleanerModel
    let showDiskUsage: () -> Void

    var body: some View {
        // The scan button sits on the right when there's room, and under the disk in a narrow window.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Design.Spacing.xl) {
                diskSummary(spacing: Design.Spacing.xl)
                Spacer(minLength: Design.Spacing.l)
                scan(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: Design.Spacing.l) {
                diskSummary(spacing: Design.Spacing.l)
                scan(alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Design.Spacing.xl)
    }

    private func diskSummary(spacing: CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            UsageRing(fraction: disk.usedFraction, tint: usageTint)
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Label(disk.volumeName, systemImage: "internaldrive")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(Format.bytes(disk.availableBytes)) kosong")
                    .font(Design.Typography.hero)
                    .monospacedDigit()
                Text("\(Format.bytes(disk.usedBytes)) dari \(Format.bytes(disk.totalBytes)) terpakai")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                // The accent color, like the app's other text buttons, rather than the blue of a web link.
                Button("Lihat yang makan tempat", action: showDiskUsage)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.top, Design.Spacing.xs)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func scan(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Design.Spacing.s) {
            Button {
                systemJunk.scan()
                developerJunk.scan()
            } label: {
                if isScanning {
                    HStack(spacing: Design.Spacing.s) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Lagi dipindai…")
                    }
                } else {
                    Label("Pindai Semua", systemImage: "sparkle.magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isScanning)
            Text("Sampah sistem dan developer sekaligus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var isScanning: Bool {
        [systemJunk, developerJunk].contains { model in
            if case .scanning = model.phase { return true }
            return false
        }
    }

    private var usageTint: Color {
        switch disk.usedFraction {
        case 0.95...: .red
        case 0.85...: .orange
        default: .accentColor
        }
    }
}

/// How full the disk is, as a ring that fills up when the page appears, with the share in the middle.
private struct UsageRing: View {
    let fraction: Double
    let tint: Color
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Format.percent(fraction))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("terpakai")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .onAppear {
            if reduceMotion {
                shown = fraction
            } else {
                withAnimation(.smooth(duration: 0.9)) { shown = fraction }
            }
        }
        .onChange(of: fraction) { _, new in shown = new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ruang terpakai")
        .accessibilityValue(Format.percent(fraction))
    }
}

/// A tool on Ringkasan: what it does, where it stands, and a click away from its page.
private struct ToolTile: View {
    let item: SidebarItem
    let status: ToolStatus?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Image(systemName: item.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .padding(.bottom, Design.Spacing.xxs)
                Text(item.title)
                    .font(.headline)
                // Two lines in a wide window. A narrow one gives the tiles less than 170 points, where some take three.
                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2...4)
                Spacer(minLength: 0)
                statusLine
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHovered ? 0.5 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Design.Motion.quick, value: isHovered)
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            switch status {
            case .pending(let text):
                text.foregroundStyle(.tertiary)
            case .busy(let text):
                HStack(spacing: Design.Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    text.foregroundStyle(.secondary)
                }
            case .found(let text):
                text.fontWeight(.semibold).foregroundStyle(.tint)
            case .info(let text):
                text.foregroundStyle(.secondary)
            case nil:
                Text(verbatim: " ")
                    .accessibilityHidden(true)
            }
        }
        .font(.callout)
        .lineLimit(1...2)
        .monospacedDigit()
        .contentTransition(.opacity)
    }
}
