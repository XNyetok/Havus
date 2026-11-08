import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, systemJunk, developerJunk, uninstaller, largeFiles, diskUsage, startupItems

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Ringkasan"
        case .systemJunk: "Sampah Sistem"
        case .developerJunk: "Sampah Developer"
        case .uninstaller: "Hapus Aplikasi"
        case .largeFiles: "File Gede & Lama"
        case .diskUsage: "Peta Disk"
        case .startupItems: "Jalan Otomatis"
        }
    }

    /// One line under the title in the toolbar, so no period at the end.
    var subtitle: LocalizedStringKey {
        switch self {
        case .overview: "Kondisi Mac kamu sekarang"
        case .systemJunk: "Cache, log, dan sisa file yang aman dibuang"
        case .developerJunk: "Sisa build dan cache tool ngoding yang bisa dibikin ulang"
        case .uninstaller: "Buang aplikasi sekalian sama file sisanya"
        case .largeFiles: "File yang makan tempat tapi jarang kamu buka"
        case .diskUsage: "Folder mana yang paling makan tempat"
        case .startupItems: "Program yang jalan sendiri di belakang layar"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .systemJunk: "sparkles"
        case .developerJunk: "hammer"
        case .uninstaller: "xmark.app"
        case .largeFiles: "doc.text.magnifyingglass"
        case .diskUsage: "chart.pie"
        case .startupItems: "power"
        }
    }
}
