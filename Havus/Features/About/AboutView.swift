import HavusCore
import SwiftUI

/// Tentang Havus: what Havus is and which version this is, what it promises, and where to find more.
struct AboutView: View {
    @Environment(UpdateCenter.self) private var updates

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.xl) {
                identity
                AboutSection(title: "Janji Havus") {
                    PromiseRow(
                        symbol: "trash", title: "Aman",
                        text:
                            "Semua yang dihapus masuk Tong Sampah dulu, kecuali isi Tong Sampah yang sengaja kamu kosongin."
                    )
                    Divider()
                    PromiseRow(
                        symbol: "hand.raised", title: "Privat",
                        text:
                            "Tanpa akun, iklan, atau telemetri. Havus cuma online buat ngecek versi baru, itu pun kalau kamu nyalain."
                    )
                    Divider()
                    PromiseRow(
                        symbol: "leaf", title: "Ringan",
                        text: "Dibikin pakai Swift dan SwiftUI, tanpa library pihak ketiga.")
                    Divider()
                    PromiseRow(
                        symbol: "chevron.left.forwardslash.chevron.right", title: "Open source",
                        text: "Kode sumbernya terbuka di GitHub, dengan lisensi MIT.")
                }
                AboutSection(title: "Tautan") {
                    LinkRow(
                        symbol: "globe", title: "Situs Havus", detail: Text(verbatim: "havus.web.id"),
                        url: Website.home(language: Bundle.main.preferredLocalizations.first))
                    Divider()
                    LinkRow(
                        symbol: "chevron.left.forwardslash.chevron.right", title: "Kode sumber",
                        detail: Text(verbatim: "github.com/XNyetok/Havus"), url: AboutLinks.repository)
                    Divider()
                    LinkRow(
                        symbol: "ladybug", title: "Lapor bug atau kasih ide",
                        detail: Text("Lewat GitHub Issues"), url: AboutLinks.newIssue)
                    Divider()
                    LinkRow(
                        symbol: "heart", title: "Dukung Havus",
                        detail: Text("Bantu biaya notarisasi Apple lewat Saweria"), url: AboutLinks.sponsor)
                }
                Text("© 2026 Debi Kurnia · Lisensi MIT")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Design.pageMargin)
            .padding(.vertical, Design.Spacing.xxl)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    private var identity: some View {
        VStack(spacing: Design.Spacing.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "Havus")
                .font(.largeTitle.weight(.bold))
            Text("Pembersih Mac yang ringan, open source, dan nggak kepo.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            version
                .font(.callout)
                .padding(.top, Design.Spacing.xs)
            HStack(spacing: Design.Spacing.s) {
                if let update = updates.availableUpdate {
                    Button("Lihat yang Baru") { updates.openChangelog(for: update.version) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Cek Versi Baru…") { updates.checkNow() }
                        .disabled(updates.isChecking)
                }
                if let current = updates.currentVersion {
                    Button("Catatan Rilis") { updates.openChangelog(for: current) }
                }
            }
            .controlSize(.large)
            .padding(.top, Design.Spacing.s)
        }
    }

    /// The running version, and what the last check said about it.
    @ViewBuilder
    private var version: some View {
        if let current = updates.currentVersion {
            HStack(spacing: Design.Spacing.s) {
                Text("Versi \(current.description)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let update = updates.availableUpdate {
                    Tag(text: "Havus \(update.version.description) udah ada", tint: .accentColor)
                } else if updates.isUpToDate {
                    Tag(text: "Udah yang terbaru")
                }
            }
        }
    }
}

/// Where the links on Tentang Havus go. They open in the browser: Havus itself never loads them.
enum AboutLinks {
    static let repository = URL(string: "https://github.com/XNyetok/Havus")
    static let newIssue = URL(string: "https://github.com/XNyetok/Havus/issues/new/choose")
    /// Donations toward the Apple Developer Program fee, so releases can be notarized.
    static let sponsor = URL(string: "https://saweria.co/nyetok")
}

/// A titled group of rows on one card.
private struct AboutSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.s) {
            Text(title)
                .font(.headline)
                .padding(.leading, Design.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content
            }
            .card(padding: 0)
        }
    }
}

/// The symbol in front of each row, in the accent color on a tinted square.
private struct RowSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Design.Radius.icon))
            .accessibilityHidden(true)
    }
}

private struct PromiseRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.m) {
            RowSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title)
                    .font(Design.Typography.rowTitle)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing.l)
        .padding(.vertical, Design.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}

private struct LinkRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: Text
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                HStack(spacing: Design.Spacing.m) {
                    RowSymbol(symbol: symbol)
                    VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                        Text(title)
                            .font(Design.Typography.rowTitle)
                        detail
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Design.Spacing.m)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .rowHighlight()
                .padding(.horizontal, Design.Spacing.l)
                .padding(.vertical, Design.Spacing.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(url.absoluteString)
            .accessibilityAddTraits(.isLink)
        }
    }
}

/// The foot of the sidebar: Havus's icon, name and version, and a click away from Tentang Havus. It also says when a
/// newer version is out.
struct AboutSidebarFooter: View {
    let isSelected: Bool
    let select: () -> Void
    @Environment(UpdateCenter.self) private var updates
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Design.Spacing.s) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Havus")
                        .font(.headline)
                    version
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Design.Spacing.s + 2)
            .padding(.vertical, Design.Spacing.s)
            .background(background, in: RoundedRectangle(cornerRadius: Design.Radius.row + 2, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.row + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Design.Motion.quick, value: isHovered)
        .padding(.horizontal, Design.Spacing.s + 2)
        .padding(.bottom, Design.Spacing.s + 2)
        .accessibilityLabel(Text("Tentang Havus"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var version: some View {
        if let update = updates.availableUpdate {
            Text("Havus \(update.version.description) udah ada")
                .foregroundStyle(.tint)
        } else if let current = updates.currentVersion {
            Text("Versi \(current.description)")
                .foregroundStyle(.secondary)
        }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return Color.primary.opacity(isHovered ? 0.08 : 0.04)
    }
}
