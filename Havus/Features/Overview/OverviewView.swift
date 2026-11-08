import HavusCore
import SwiftUI

struct OverviewView: View {
    let open: (SidebarItem) -> Void
    @State private var disk: DiskSpace?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xl) {
                UpdateBanner()
                if let disk {
                    DiskCard(disk: disk) { open(.diskUsage) }
                }
                FullDiskAccessBanner()
                // Always 2×2 with the four cleanup tools, so they stay balanced at any window width.
                // Jalan Otomatis is in the sidebar only.
                Grid(horizontalSpacing: Design.Spacing.l, verticalSpacing: Design.Spacing.l) {
                    GridRow {
                        FeatureTile(item: .systemJunk) { open(.systemJunk) }
                        FeatureTile(item: .developerJunk) { open(.developerJunk) }
                    }
                    GridRow {
                        FeatureTile(item: .uninstaller) { open(.uninstaller) }
                        FeatureTile(item: .largeFiles) { open(.largeFiles) }
                    }
                }
                AutomaticCheckPrompt()
                Label("Semua proses jalan di Mac kamu. Havus nggak ngirim data kamu ke internet.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Design.pageMargin)
            .frame(maxWidth: Design.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { disk = try? DiskSpace.startupDisk() }
    }
}

private struct DiskCard: View {
    let disk: DiskSpace
    let showDiskUsage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label(disk.volumeName, systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("\(Format.bytes(disk.usedBytes)) dari \(Format.bytes(disk.totalBytes)) terpakai")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("\(Format.bytes(disk.availableBytes)) kosong")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: disk.usedFraction)
                .tint(usageTint)
                .accessibilityLabel("Ruang terpakai")
            // The accent color, like the app's other text buttons, rather than the blue of a web link.
            Button("Lihat yang makan tempat", action: showDiskUsage)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .card()
    }

    private var usageTint: Color {
        switch disk.usedFraction {
        case 0.95...: .red
        case 0.85...: .orange
        default: .accentColor
        }
    }
}

private struct FeatureTile: View {
    let item: SidebarItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Design.Spacing.s) {
                Image(systemName: item.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(height: 28)
                Text(item.title)
                    .font(.headline)
                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
