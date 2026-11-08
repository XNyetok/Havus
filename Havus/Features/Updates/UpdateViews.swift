import HavusCore
import SwiftUI

/// On Ringkasan, when the last check found a newer version.
struct UpdateBanner: View {
    @Environment(UpdateCenter.self) private var updates

    var body: some View {
        if let update = updates.availableUpdate, !updates.isBannerHidden {
            NoticeBanner(
                tone: .success,
                symbol: "arrow.down",
                title: UpdateCopy.title(update),
                message: UpdateCopy.message(update)
            ) {
                Button("Lihat yang Baru") { updates.openChangelog(for: update.version) }
                Button("Nanti") { updates.isBannerHidden = true }
            }
        }
    }
}

/// On Ringkasan until the user decides whether Havus may check for new versions by itself.
struct AutomaticCheckPrompt: View {
    @Environment(UpdateCenter.self) private var updates

    var body: some View {
        if !updates.hasChosenAutomaticChecks {
            NoticeBanner(
                tone: .neutral,
                symbol: "bell.badge",
                title: Text("Mau dikabarin kalau ada versi baru?"),
                message: Text(
                    "Sehari sekali, Havus bisa ngecek lewat internet apakah ada versi baru. Nggak ada data apa pun soal kamu atau Mac kamu yang dikirim. Bisa kamu ubah kapan aja di menu **Havus → Cek Versi Baru Otomatis**."
                )
            ) {
                Button("Nyalain") { updates.setChecksAutomatically(true) }
                Button("Nggak Usah") { updates.setChecksAutomatically(false) }
            }
        }
    }
}

/// "Cek Versi Baru" and its toggle, in the app menu right below "About Havus", where Mac apps keep them.
struct UpdateCommands: Commands {
    let updates: UpdateCenter

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Cek Versi Baru…") { updates.checkNow() }
                .disabled(updates.isChecking)
            Toggle(
                "Cek Versi Baru Otomatis",
                isOn: Binding(get: { updates.checksAutomatically }, set: { updates.setChecksAutomatically($0) })
            )
        }
    }
}

extension View {
    /// Answers "Cek Versi Baru…".
    func updateCheckAlert(_ updates: UpdateCenter) -> some View {
        modifier(UpdateCheckAlert(updates: updates))
    }
}

private struct UpdateCheckAlert: ViewModifier {
    let updates: UpdateCenter

    func body(content: Content) -> some View {
        content.alert(
            title(updates.manualResult),
            isPresented: Binding(get: { updates.manualResult != nil }, set: { if !$0 { updates.manualResult = nil } }),
            presenting: updates.manualResult
        ) { result in
            if case .available(let update) = result {
                Button("Lihat yang Baru") { updates.openChangelog(for: update.version) }
                Button("Nanti", role: .cancel) {}
            } else {
                Button("Oke", role: .cancel) {}
            }
        } message: { result in
            message(result)
        }
    }

    private func title(_ result: UpdateCenter.CheckResult?) -> Text {
        switch result {
        case .available(let update): UpdateCopy.title(update)
        case .upToDate, nil: Text("Havus kamu udah yang terbaru")
        case .failed: Text("Nggak bisa ngecek versi baru")
        }
    }

    private func message(_ result: UpdateCenter.CheckResult) -> Text {
        switch result {
        case .available(let update): UpdateCopy.message(update)
        case .upToDate:
            if let current = updates.currentVersion {
                Text("Versi \(current.description) yang kamu pakai ini udah yang paling baru.")
            } else {
                Text("Versi yang kamu pakai ini udah yang paling baru.")
            }
        case .failed: Text("Cek koneksi internet kamu, lalu coba lagi nanti.")
        }
    }
}

/// Shared by the banner and the alert.
private enum UpdateCopy {
    static func title(_ update: UpdateCenter.Update) -> Text {
        Text("Havus \(update.version.description) udah ada")
    }

    static func message(_ update: UpdateCenter.Update) -> Text {
        Text(
            "Kamu masih pakai versi \(update.current.description). Lihat apa aja yang baru, sekalian cara update-nya, di havus.web.id."
        )
    }
}
