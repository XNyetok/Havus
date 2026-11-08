import Foundation

/// Links to havus.web.id. The site is in Indonesian, with every page in English too under /en/, so links follow the
/// language Havus runs in.
public enum Website {
    /// The home page, for Tentang Havus.
    public static func home(language: String?) -> URL? {
        URL(string: isEnglish(language) ? "https://havus.web.id/en/" : "https://havus.web.id/")
    }

    /// `language` is the one Havus runs in, such as `en` or `id`, from `Bundle.main.preferredLocalizations`. Any other
    /// language gets the Indonesian pages, just as the app falls back to Indonesian.
    static func isEnglish(_ language: String?) -> Bool {
        language.map { Locale(identifier: $0).language.languageCode == .english } ?? false
    }
}
