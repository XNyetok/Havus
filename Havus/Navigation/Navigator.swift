import Observation

/// The page the main window shows. Shared with the menu bar, so **Havus → Tentang Havus** can open its page.
@MainActor
@Observable
final class Navigator {
    var selection: SidebarItem = .overview
}
