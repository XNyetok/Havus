import AppKit
import SwiftUI

/// Havus → Pengaturan… (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("Umum", systemImage: "gearshape") }
            ExclusionsPane()
                .tabItem { Label("Pengecualian", systemImage: "hand.raised") }
        }
        .frame(width: 540)
    }
}

/// Update checks, Full Disk Access and the language, each with a word on what it does.
private struct GeneralPane: View {
    @Environment(UpdateCenter.self) private var updates
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Cek versi baru otomatis",
                    isOn: Binding(
                        get: { updates.checksAutomatically }, set: { updates.setChecksAutomatically($0) }))
                LabeledContent("Versi yang kamu pakai") {
                    HStack(spacing: Design.Spacing.m) {
                        if let current = updates.currentVersion {
                            Text(verbatim: current.description)
                                .monospacedDigit()
                        }
                        Button("Cek Sekarang") { updates.checkNow() }
                            .disabled(updates.isChecking)
                    }
                }
            } header: {
                Text("Versi baru")
            } footer: {
                Text(
                    "Sehari sekali, Havus nanya nomor versi terbaru ke GitHub. Nggak ada data apa pun soal kamu atau Mac kamu yang dikirim."
                )
                .settingsFootnote()
            }

            Section {
                LabeledContent("Akses Disk Penuh") {
                    if permissions.hasFullDiskAccess {
                        Label("Aktif", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    } else {
                        Button("Buka Pengaturan") { permissions.openFullDiskAccessSettings() }
                    }
                }
            } header: {
                Text("Izin")
            } footer: {
                Text("Biar Havus bisa ngecek semua lokasi, termasuk Tong Sampah, lampiran Mail, dan data app lain.")
                    .settingsFootnote()
            }

            Section {
                LabeledContent("Ngikutin bahasa Mac kamu") {
                    Button("Buka Bahasa & Wilayah") { openLanguageSettings() }
                }
            } header: {
                Text("Bahasa")
            } footer: {
                Text(
                    "Mau bahasa lain khusus buat Havus? Tambahin Havus di bagian **Applications**, terus pilih bahasanya."
                )
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        // Coming back from System Settings, the permission may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    /// System Settings → General → Language & Region, where the user can also pick a language for Havus alone.
    private func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

extension Text {
    /// The note under a group of settings.
    fileprivate func settingsFootnote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The files and folders Havus never touches.
private struct ExclusionsPane: View {
    @Environment(ExclusionStore.self) private var exclusions
    @State private var selection: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.m) {
            Text(
                "Havus nggak bakal nyentuh file dan folder di sini, termasuk semua isinya. Semuanya nggak muncul di hasil pindai, dan nggak bakal dipindah ke Tong Sampah atau dihapus."
            )
            .fixedSize(horizontal: false, vertical: true)

            // The list with its + and − buttons attached underneath, like lists in macOS's own settings.
            VStack(spacing: 0) {
                List(exclusions.urls, id: \.self, selection: $selection) { url in
                    Label {
                        Text(Format.path(url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(Format.path(url))
                    } icon: {
                        FileIcon(url: url, size: 16)
                    }
                }
                .listStyle(.plain)
                .alternatingRowBackgrounds()
                .scrollContentBackground(.hidden)
                .overlay {
                    if exclusions.urls.isEmpty {
                        Text("Belum ada yang dikecualiin.")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDeleteCommand(perform: removeSelection)
                Divider()
                HStack(spacing: 0) {
                    Button(action: add) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .help("Tambah file atau folder")
                    .accessibilityLabel("Tambah file atau folder")
                    Divider()
                        .frame(height: 14)
                    Button(action: removeSelection) {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .help("Hapus dari daftar")
                    .accessibilityLabel("Hapus dari daftar")
                    .disabled(selection.isEmpty)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, Design.Spacing.xs)
            }
            .frame(height: 240)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)
                    .strokeBorder(Design.hairline)
            }

            Text("Bisa juga dari hasil pindai: klik kanan sebuah item, lalu pilih **Masukin ke Pengecualian**.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Spacing.xl)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Pilih file atau folder yang nggak boleh disentuh Havus.")
        panel.prompt = String(localized: "Kecualiin")
        guard panel.runModal() == .OK else { return }
        exclusions.add(panel.urls)
    }

    private func removeSelection() {
        exclusions.remove(selection)
        selection = []
    }
}
