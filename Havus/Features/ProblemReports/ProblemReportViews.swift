import SwiftUI

/// "Laporkan Masalah…" in the Help menu, in place of the help book Havus doesn't have.
struct ProblemReportCommands: Commands {
    let reports: ProblemReportCenter

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Laporkan Masalah…") { reports.reportProblem() }
        }
    }
}

extension View {
    /// Offers a new crash report, and answers "Laporkan Masalah…".
    func problemReportAlert(_ reports: ProblemReportCenter) -> some View {
        modifier(ProblemReportAlert(reports: reports))
    }
}

private struct ProblemReportAlert: ViewModifier {
    let reports: ProblemReportCenter

    func body(content: Content) -> some View {
        content.alert(
            title(reports.prompt),
            isPresented: Binding(get: { reports.prompt != nil }, set: { if !$0 { reports.prompt = nil } }),
            presenting: reports.prompt
        ) { prompt in
            Button("Lapor lewat GitHub") { reports.send(prompt, via: .gitHub) }
            Button("Kirim lewat Email") { reports.send(prompt, via: .email) }
            if case .crash = prompt {
                Button("Nggak Usah", role: .cancel) {}
            } else {
                Button("Batal", role: .cancel) {}
            }
        } message: { prompt in
            message(prompt)
        }
    }

    private func title(_ prompt: ProblemReportCenter.Prompt?) -> Text {
        switch prompt {
        case .crash: Text("Havus sempat berhenti mendadak")
        case .problem, nil: Text("Laporkan masalah")
        }
    }

    private func message(_ prompt: ProblemReportCenter.Prompt) -> Text {
        switch prompt {
        case .crash:
            Text(
                "macOS nyimpen laporan crash-nya di Mac kamu. Isinya info teknis soal Havus dan macOS, bukan isi file kamu. Kalau kamu kirim, bug-nya bisa lebih cepat dibenerin. Havus nunjukin laporan itu dan catatan aktivitasnya di Finder, kamu tinggal lampirin."
            )
        case .problem(recentCrash: .some):
            Text(
                "Ceritain apa yang terjadi lewat GitHub, atau lewat email kalau kamu nggak punya akun GitHub. Havus juga nunjukin laporan crash terakhir dan catatan aktivitasnya di Finder, biar bisa kamu lampirin."
            )
        case .problem(recentCrash: nil):
            Text(
                "Ceritain apa yang terjadi lewat GitHub, atau lewat email kalau kamu nggak punya akun GitHub. Havus juga nunjukin catatan aktivitasnya di Finder, biar bisa kamu lampirin."
            )
        }
    }
}
