import Foundation

/// Sizes and dates in the language Havus runs in (Indonesian or English), so they match the text around them.
enum Format {
    /// The user's locale. macOS gives it the language Havus picked from its localizations, together with the user's
    /// region and number settings.
    static var locale: Locale { .autoupdatingCurrent }

    /// `1234567890` → `1,23 GB` or `1.23 GB`, as the user's region writes numbers. `0` → `0 byte` in Indonesian or
    /// `0 bytes` in English (not "Nol kB").
    static func bytes(_ value: Int64) -> String {
        // Below 1 kB the system's Indonesian format says "bita" (seen on macOS 27), so "0 file dipilih · 0 bita".
        // Use the "byte" everyone says instead. The string catalog makes it "bytes" in English.
        let text =
            value >= 1000
            ? value.formatted(ByteCountFormatStyle(style: .file, spellsOutZero: false, locale: locale))
            : String(localized: "\(value) byte")
        // A no-break space keeps the number and its unit on one line when a sentence wraps.
        return text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// `0.42` → `42%`, as the user's region writes it. A share that rounds to zero but isn't says `<1%`.
    static func percent(_ fraction: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Percent(locale: locale).precision(.fractionLength(0))
        guard fraction > 0, fraction < 0.005 else { return fraction.formatted(style) }
        return "<" + 0.01.formatted(style)
    }

    /// `3600` → `1 jam` or `1 hour`; `5400` → `1 jam, 30 menit` or `1 hour, 30 minutes`.
    static func duration(seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2).locale(locale))
    }

    /// Relative date, e.g. `3 bulan yang lalu` or `3 months ago`.
    static func relativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }

    /// `/Users/someone/Downloads/` → `~/Downloads`
    static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let home = URL.homeDirectory.path(percentEncoded: false)
        return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
    }
}
