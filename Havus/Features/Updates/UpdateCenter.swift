import AppKit
import HavusCore
import Observation

/// Lets the user know when a newer Havus is out. Havus can't install it by itself, so it links to the release on the
/// changelog at havus.web.id, in the language Havus runs in. The page also has the download and the update steps.
///
/// Nothing goes online until the user asks: either with "Cek Versi Baru…", or by turning on the daily check.
@MainActor
@Observable
final class UpdateCenter {
    /// A version newer than the running one.
    struct Update: Equatable {
        let version: AppVersion
        let current: AppVersion
    }

    enum CheckResult: Equatable {
        case available(Update)
        case upToDate
        case failed
    }

    /// The running version, from `CFBundleShortVersionString`. Without one, Havus never claims an update.
    let currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        .flatMap(AppVersion.init)

    /// Whether Havus checks once a day by itself. Off until the user turns it on.
    private(set) var checksAutomatically: Bool
    /// Whether the user answered "Mau dikabarin kalau ada versi baru?", either way.
    private(set) var hasChosenAutomaticChecks: Bool
    private(set) var isChecking = false
    /// The answer to a check the user started from the menu, shown in an alert.
    var manualResult: CheckResult?
    /// "Nanti" hides the banner until the next launch.
    var isBannerHidden = false

    /// The newest version the last check found, kept between launches.
    private var latestVersion: AppVersion?
    private var lastCheck: Date?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        checksAutomatically = defaults.bool(forKey: Key.automatic)
        hasChosenAutomaticChecks = defaults.bool(forKey: Key.chosen)
        latestVersion = defaults.string(forKey: Key.latestVersion).flatMap(AppVersion.init)
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// Whether the last check found no newer version. `false` before any check, since Havus doesn't know yet.
    var isUpToDate: Bool { latestVersion != nil && availableUpdate == nil }

    /// A version newer than the running one, if the last check found it.
    var availableUpdate: Update? {
        guard let latestVersion, let currentVersion, latestVersion > currentVersion else { return nil }
        return Update(version: latestVersion, current: currentVersion)
    }

    func setChecksAutomatically(_ isOn: Bool) {
        checksAutomatically = isOn
        hasChosenAutomaticChecks = true
        defaults.set(isOn, forKey: Key.automatic)
        defaults.set(true, forKey: Key.chosen)
        checkIfDue()
    }

    /// The daily check: runs when it's on and the last check was a day or more ago.
    func checkIfDue() {
        guard checksAutomatically, UpdateCheck.isDue(lastCheck: lastCheck) else { return }
        check(manual: false)
    }

    /// "Cek Versi Baru…": always asks GitHub, then answers in an alert.
    func checkNow() {
        check(manual: true)
    }

    func openChangelog(for version: AppVersion) {
        // macOS picks the language Havus runs in from the user's languages; the changelog follows it.
        guard let url = UpdateCheck.changelogURL(for: version, language: Bundle.main.preferredLocalizations.first)
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func check(manual: Bool) {
        guard !isChecking else { return }
        isChecking = true
        // Recorded even when the check fails, so an offline Mac doesn't try again every time Havus comes forward.
        lastCheck = .now
        defaults.set(lastCheck, forKey: Key.lastCheck)

        Task {
            defer { isChecking = false }
            do {
                let latest = try await UpdateCheck.latestVersion()
                latestVersion = latest
                defaults.set(latest.description, forKey: Key.latestVersion)
                if manual {
                    manualResult = availableUpdate.map(CheckResult.available) ?? .upToDate
                }
            } catch {
                if manual {
                    manualResult = .failed
                }
            }
        }
    }

    private enum Key {
        static let automatic = "UpdateCheck.automatic"
        static let chosen = "UpdateCheck.chosen"
        static let latestVersion = "UpdateCheck.latestVersion"
        static let lastCheck = "UpdateCheck.lastCheck"
    }
}
