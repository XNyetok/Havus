import SwiftUI

// MARK: - Page structure

/// A page's content in one of its states (idle, scanning, results, …). Switching states crossfades instead of jumping.
/// `key` names the state: give it no counters or sizes, or every progress update would start a new crossfade.
struct PhaseContent<Key: Hashable, Content: View>: View {
    let key: Key
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            content
                .id(key)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Design.Motion.page, value: key)
    }
}

/// The top of a results page: its key number in large type with a few words after it, and room below for notes.
/// It stays put while the list under it scrolls.
struct SummaryHeader<Value: View, Notes: View>: View {
    private let value: Value
    private let caption: Text
    private let notes: Notes

    init(@ViewBuilder value: () -> Value, caption: () -> Text, @ViewBuilder notes: () -> Notes) {
        self.value = value()
        self.caption = caption()
        self.notes = notes()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.s) {
                value
                    .font(Design.Typography.metric)
                    .monospacedDigit()
                caption
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            notes
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.pageMargin)
        .padding(.top, Design.Spacing.l)
        .padding(.bottom, Design.Spacing.m)
    }
}

extension SummaryHeader where Notes == EmptyView {
    init(@ViewBuilder value: () -> Value, caption: () -> Text) {
        self.init(value: value, caption: caption, notes: { EmptyView() })
    }
}

/// A size whose digits roll to the new value when it changes.
struct RollingSize: View {
    let bytes: Int64
    var isComplete = true

    var body: some View {
        SizeText(bytes: bytes, isComplete: isComplete)
            .contentTransition(.numericText(value: Double(bytes)))
            .animation(Design.Motion.quick, value: bytes)
    }
}

/// Rows in a scrolling column on the page's edges, under a header that stays put. A plain stack rather than a `List`,
/// which adds insets of its own that differ between macOS versions, so rows and the header wouldn't share one left
/// edge. The header is pinned inside the scroll view rather than above it, so when a mouse makes the scroll bar take
/// up room, it narrows the header and the rows alike, and their right edges still line up.
struct RowList<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    content
                        .padding(.horizontal, Design.pageMargin)
                    Color.clear
                        .frame(height: Design.Spacing.s)
                } header: {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        Color.clear
                            .frame(height: Design.Spacing.s)
                    }
                    .background(.background)
                }
            }
        }
    }
}

/// The line between two rows, starting where the rows' text starts.
struct RowDivider: View {
    let inset: CGFloat

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

/// Bottom bar with a page's summary on the left and its primary action on the right. In a narrow column, such as Hapus
/// Aplikasi's, the summary goes above the action, so the action's label, which can name an app, is never cut short.
///
/// Text in it wraps on its own. Never give it `.fixedSize(horizontal: false, vertical: true)`: the page's minimum
/// height is measured with the text squeezed narrow, where it grows hundreds of points tall, and the whole window
/// content, sidebar included, then gets laid out taller than the window and cut off at both ends.
struct ActionBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SideBySideOrStacked(spacing: Design.Spacing.m, minimumFirstWidth: 180, stackedAlignment: .trailing) {
            HStack(spacing: Design.Spacing.s) { leading }
                .lineLimit(2)
            HStack(spacing: Design.Spacing.s) { trailing }
        }
        .padding(.horizontal, Design.pageMargin)
        .padding(.vertical, Design.Spacing.m)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Text and its buttons side by side, or the buttons below the text once the text would get less than
/// `minimumFirstWidth` next to them, as in a narrow column. The buttons always get their full width, so a label is
/// never cut short, and the text never gets squeezed into a sliver.
struct SideBySideOrStacked: Layout {
    enum StackedAlignment {
        case leading, trailing
    }

    var spacing: CGFloat
    var minimumFirstWidth: CGFloat
    /// Where the buttons go when they're below the text.
    var stackedAlignment: StackedAlignment

    // The text gets the height on offer, like in an HStack. Offered no height limit, it would grow hundreds of points
    // tall while the window measures its minimum size with everything squeezed narrow (see ActionBar).
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let second = subviews[1].sizeThatFits(.unspecified)
        let gap = second.width > 0 ? spacing : 0
        guard let width = proposal.width else {
            let first = subviews[0].sizeThatFits(.unspecified)
            return CGSize(width: first.width + gap + second.width, height: max(first.height, second.height))
        }
        if isStacked(width: width, second: second) {
            let height = proposal.height.map { max(0, $0 - spacing - second.height) }
            let first = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: height))
            return CGSize(width: width, height: first.height + spacing + second.height)
        }
        let first = subviews[0].sizeThatFits(
            ProposedViewSize(width: max(0, width - gap - second.width), height: proposal.height))
        return CGSize(width: width, height: max(first.height, second.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let second = subviews[1].sizeThatFits(.unspecified)
        let gap = second.width > 0 ? spacing : 0
        let secondProposal = ProposedViewSize(width: min(second.width, bounds.width), height: second.height)
        if isStacked(width: bounds.width, second: second) {
            let height = max(0, bounds.height - spacing - second.height)
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: height))
            let y = bounds.minY + height + spacing
            switch stackedAlignment {
            case .leading:
                subviews[1].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: secondProposal)
            case .trailing:
                subviews[1].place(at: CGPoint(x: bounds.maxX, y: y), anchor: .topTrailing, proposal: secondProposal)
            }
        } else {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: max(0, bounds.width - gap - second.width), height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: secondProposal)
        }
    }

    /// Without buttons, the text keeps the whole width.
    private func isStacked(width: CGFloat, second: CGSize) -> Bool {
        second.width > 0 && width - spacing - second.width < minimumFirstWidth
    }
}

/// The toolbar button that runs a page's scan again, with ⌘R. A page with other controls in its toolbar shows only the
/// icon, so the page's subtitle keeps its room; the title is still its tooltip and what VoiceOver reads.
struct RescanButton: View {
    var title: LocalizedStringKey = "Pindai Ulang"
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if showsTitle {
                Label(title, systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
            } else {
                Label(title, systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .help(Text(title))
    }
}

// MARK: - Messages

/// A symbol on a tinted disc, at the top of an empty page or a scan in progress.
struct SymbolDisc: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A page with nothing to list: what it does or found, and what to do next.
struct EmptyState<Actions: View>: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: Text
    let message: Text
    /// Something to know before the first step, such as a permission macOS is going to ask for.
    var note: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Design.Spacing.m) {
            SymbolDisc(symbol: symbol, tint: tint)
                .padding(.bottom, Design.Spacing.xs)
            title
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            message
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Design.messageWidth)
            if let note {
                NoticeBanner(tone: .warning, symbol: "lock.shield", message: note)
                    .frame(maxWidth: Design.messageWidth)
                    .padding(.top, Design.Spacing.xs)
            }
            HStack(spacing: Design.Spacing.s) {
                actions
            }
            .controlSize(.large)
            .padding(.top, Design.Spacing.s)
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String, tint: Color = .accentColor, title: Text, message: Text) {
        self.init(symbol: symbol, tint: tint, title: title, message: message, actions: { EmptyView() })
    }
}

/// While a page scans or cleans: what it's doing, how far it got, and a way to stop.
struct ScanProgress: View {
    let symbol: String
    let title: Text
    /// How far it got, from 0 to 1. `nil` while that isn't known.
    var fraction: Double?
    var detail: Text?
    var cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Design.Spacing.m) {
            SymbolDisc(symbol: symbol)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .padding(.bottom, Design.Spacing.xs)
            title
                .font(.headline)
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                        .animation(Design.Motion.quick, value: fraction)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            .frame(width: 280)
            if let detail {
                detail
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let cancel {
                Button("Batal", action: cancel)
                    .padding(.top, Design.Spacing.xs)
            }
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A note on a page: a permission to grant, a warning, or what just happened. One style for every page.
struct NoticeBanner<Actions: View>: View {
    enum Tone {
        /// Something to know.
        case neutral
        /// Something that went well, such as files moved to the Trash.
        case success
        /// Something in the way, such as a missing permission.
        case warning
    }

    let tone: Tone
    let symbol: String
    var title: Text?
    let message: Text
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Design.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Design.Radius.icon, style: .continuous)
                )
                .accessibilityHidden(true)
            // In a narrow column, such as Hapus Aplikasi's, the buttons go below the text.
            SideBySideOrStacked(spacing: Design.Spacing.m, minimumFirstWidth: 240, stackedAlignment: .leading) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    if let title {
                        title
                            .font(.headline)
                    }
                    message
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Design.Spacing.s) {
                    actions
                }
                .fixedSize()
            }
        }
        .padding(Design.Spacing.m)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.16))
        }
    }

    private var tint: Color {
        switch tone {
        case .neutral: .secondary
        case .success: .accentColor
        case .warning: .orange
        }
    }
}

extension NoticeBanner where Actions == EmptyView {
    init(tone: Tone, symbol: String, title: Text? = nil, message: Text) {
        self.init(tone: tone, symbol: symbol, title: title, message: message, actions: { EmptyView() })
    }
}

/// Explains why Full Disk Access helps, and links to System Settings. Hidden once granted.
struct FullDiskAccessBanner: View {
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        if !permissions.hasFullDiskAccess {
            NoticeBanner(
                tone: .warning,
                symbol: "lock.shield",
                title: Text("Akses Disk Penuh belum aktif"),
                message: Text(
                    "Tanpa izin ini, beberapa lokasi (kayak Tong Sampah, lampiran Mail, dan data app lain) bakal dilewati. Buka **Privacy & Security → Full Disk Access**, terus nyalain Havus."
                )
            ) {
                Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                Button("Cek Lagi") { permissions.refresh() }
            }
        }
    }
}

/// What to expect without Full Disk Access, before a page looks through the whole home folder.
enum FullDiskAccessNote {
    static var text: Text {
        Text(
            "Akses Disk Penuh belum nyala. macOS bakal nanya izin buat Desktop, Dokumen, dan Unduhan, sedangkan pustaka Foto dan Musik dilewati dulu."
        )
    }
}

// MARK: - Surfaces

/// Subtle rounded surface for grouped content.
private struct CardBackground: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .strokeBorder(Design.hairline)
            }
    }
}

/// A soft highlight behind a row that reacts to clicks, shown while the pointer is over it, or for good while
/// `isHighlighted`. It reaches a little past the row on both sides, so the row's content stays on the page's edge.
private struct RowHighlight: ViewModifier {
    let isHighlighted: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Design.hover)
                    .padding(.horizontal, -Design.Spacing.s)
                    .opacity(isHighlighted || isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .animation(Design.Motion.quick, value: isHovered)
    }
}

extension View {
    func card(padding: CGFloat = Design.Spacing.l) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func rowHighlight(_ isHighlighted: Bool = false) -> some View {
        modifier(RowHighlight(isHighlighted: isHighlighted))
    }
}

// MARK: - Selection

enum CheckState {
    case on, off, mixed

    /// What VoiceOver says after the row, e.g. "Cache npm, 1,2 GB, Dipilih".
    var accessibilityValue: LocalizedStringKey {
        switch self {
        case .on: "Dipilih"
        case .off: "Nggak dipilih"
        case .mixed: "Sebagian dipilih"
        }
    }
}

/// Checkbox that can also show a mixed state, for "everything in this group".
/// VoiceOver skips the box itself: put `selectableRow(_:toggle:)` on the row around it.
struct SelectionBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Design.Column.checkbox, height: Design.Column.checkbox)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Design.Motion.quick, value: state)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .off: "square"
        case .mixed: "minus.square.fill"
        }
    }
}

extension View {
    /// Makes a row with a `SelectionBox` read as one checkbox in VoiceOver: its name, details and size,
    /// then the selection state. Without it, every box in a list only said "Pilih", with no item name.
    func selectableRow(_ state: CheckState, toggle: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityValue(state.accessibilityValue)
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { toggle() }
    }

    /// The same for a row that opens a group: VoiceOver's default action opens or closes the group, so selecting
    /// everything in it is a named action.
    func selectableGroupLabel(_ state: CheckState, toggleAll: @escaping () -> Void) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityValue(state.accessibilityValue)
            .accessibilityAction(named: state == .on ? "Batal pilih semua" : "Pilih semua") { toggleAll() }
    }
}

// MARK: - Small parts

/// Small capsule label, e.g. "Cek dulu".
struct Tag: View {
    let text: LocalizedStringKey
    var tint: Color = .secondary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            // In light mode, orange and red text on the pale capsule reads at only about 2:1 and 3:1, so darken it there.
            .brightness(colorScheme == .light ? -0.3 : 0)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// A size, or what Havus knows about it when it couldn't read everything, instead of looking empty ("0 byte").
struct SizeText: View {
    let bytes: Int64
    /// `false` when Havus couldn't read all of it, so `bytes` is only what it could read.
    let isComplete: Bool

    var body: some View {
        if isComplete {
            Text(Format.bytes(bytes))
        } else if bytes == 0 {
            Text("Nggak kebaca")
                .help("macOS nggak ngizinin Havus baca isinya, jadi ukurannya belum ketahuan.")
        } else {
            Text(verbatim: "\(Format.bytes(bytes))+")
                .help("Sebagian isinya nggak bisa dibaca Havus, jadi ukuran aslinya bisa lebih gede.")
                .accessibilityLabel("Lebih dari \(Format.bytes(bytes))")
        }
    }

    /// What VoiceOver says for the size, for a row that names itself.
    static func spoken(bytes: Int64, isComplete: Bool) -> String {
        if isComplete { return Format.bytes(bytes) }
        if bytes == 0 { return String(localized: "Nggak kebaca") }
        return String(localized: "Lebih dari \(Format.bytes(bytes))")
    }
}

/// App icon as Finder shows it.
struct FileIcon: View {
    let url: URL
    var size: CGFloat = Design.Column.icon

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
