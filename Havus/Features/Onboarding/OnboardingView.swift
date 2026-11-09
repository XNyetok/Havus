import AppKit
import SwiftUI

/// Shown once, on the first launch: how Havus keeps files safe, Full Disk Access, and whether to hear about new
/// versions. The last step needs an answer, since nothing goes online until the user says so.
struct OnboardingView: View {
    let finish: () -> Void
    @Environment(PermissionCenter.self) private var permissions
    @Environment(UpdateCenter.self) private var updates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome, fullDiskAccess, updates
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Design.Spacing.xxl)
            .padding(.top, Design.Spacing.xxl)
            .clipped()
            HStack(spacing: Design.Spacing.s) {
                PageDots(count: Step.allCases.count, current: step.rawValue)
                Spacer()
                buttons
            }
            .controlSize(.large)
            .padding(Design.Spacing.xl)
        }
        .frame(width: 520, height: 480)
        .interactiveDismissDisabled()
        // Coming back from System Settings, Full Disk Access may be on now.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingStep(
                title: Text("Selamat datang di Havus"),
                message: Text("Pembersih Mac yang ringan, open source, dan nggak kepo.")
            ) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            } details: {
                OnboardingPoint(
                    symbol: "checkmark.circle", title: "Kamu yang milih",
                    text: "Havus cuma nunjukin yang bisa dibersihin. Nggak ada yang dihapus tanpa persetujuan kamu.")
                OnboardingPoint(
                    symbol: "trash", title: "Masuk Tong Sampah dulu",
                    text: "Masih bisa dibalikin, kecuali isi Tong Sampah yang sengaja kamu kosongin.")
                OnboardingPoint(
                    symbol: "hand.raised", title: "Semuanya di Mac kamu",
                    text: "Nggak ada akun, iklan, atau telemetri.")
            }

        case .fullDiskAccess:
            OnboardingStep(
                title: Text("Nyalain Akses Disk Penuh"),
                message: Text(
                    "macOS ngunci beberapa lokasi, kayak Tong Sampah, lampiran Mail, dan data app lain. Dengan izin ini Havus bisa ngecek semuanya, dan tetap cuma ngehapus yang kamu pilih."
                )
            ) {
                SymbolDisc(symbol: "lock.shield")
            } details: {
                if permissions.hasFullDiskAccess {
                    Label("Akses Disk Penuh udah aktif", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                } else {
                    OnboardingPoint(symbol: "1.circle", title: "Klik Buka Pengaturan", text: nil)
                    OnboardingPoint(symbol: "2.circle", title: "Nyalain Havus di daftar Akses Disk Penuh", text: nil)
                    OnboardingPoint(symbol: "3.circle", title: "Balik ke Havus", text: nil)
                }
            }

        case .updates:
            OnboardingStep(
                title: Text("Mau dikabarin kalau ada versi baru?"),
                message: Text(
                    "Sehari sekali, Havus bisa ngecek lewat internet apakah ada versi baru. Nggak ada data apa pun soal kamu atau Mac kamu yang dikirim. Bisa kamu ubah kapan aja di **Pengaturan → Umum**."
                )
            ) {
                SymbolDisc(symbol: "bell.badge")
            } details: {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch step {
        case .welcome:
            Button("Lanjut") { go(to: .fullDiskAccess) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .fullDiskAccess:
            if permissions.hasFullDiskAccess {
                Button("Lanjut") { go(to: .updates) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Nanti Aja") { go(to: .updates) }
                Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .updates:
            Button("Nggak Usah") { answer(false) }
            Button("Nyalain") { answer(true) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity))
    }

    private func go(to next: Step) {
        withAnimation(Design.Motion.page) { step = next }
    }

    private func answer(_ checksAutomatically: Bool) {
        updates.setChecksAutomatically(checksAutomatically)
        finish()
    }
}

/// One step: a picture, a title, a few words, and what to know or do.
private struct OnboardingStep<Picture: View, Details: View>: View {
    let title: Text
    let message: Text
    @ViewBuilder var picture: Picture
    @ViewBuilder var details: Details

    var body: some View {
        VStack(spacing: Design.Spacing.l) {
            VStack(spacing: Design.Spacing.s) {
                picture
                    .padding(.bottom, Design.Spacing.xs)
                title
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                message
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Design.Spacing.m) {
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A line in a step: a symbol, a short title, and maybe a sentence under it.
private struct OnboardingPoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey?

    var body: some View {
        HStack(alignment: text == nil ? .center : .top, spacing: Design.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Design.Radius.icon))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(title)
                    .font(Design.Typography.rowTitle)
                if let text {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Which step is on screen, as a row of dots.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Design.Spacing.s) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .animation(Design.Motion.quick, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Langkah \(current + 1) dari \(count)"))
    }
}
