import SwiftUI

/// Design tokens. Keep the UI calm: one accent color, generous spacing, few borders, and one left edge per page.
enum Design {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// The space between a page's edges and its content. Summaries, rows and the action bar all start on it, under the
    /// page's name in the toolbar, so every page has one left edge.
    static let pageMargin: CGFloat = 20

    enum Radius {
        static let card: CGFloat = 14
        /// The highlight behind a row under the pointer.
        static let row: CGFloat = 8
        /// The tinted square behind a banner's icon.
        static let icon: CGFloat = 7
    }

    /// Keeps lines readable on large displays.
    static let readableWidth: CGFloat = 880
    /// Centered text, such as the message on an empty page.
    static let messageWidth: CGFloat = 440
    /// A paragraph that runs the width of a page, such as a note under a list.
    static let paragraphWidth: CGFloat = 640

    /// The columns rows share, so checkboxes, icons and sizes line up from row to row.
    enum Column {
        static let checkbox: CGFloat = 20
        static let icon: CGFloat = 28
        static let size: CGFloat = 84
        static let chevron: CGFloat = 16
    }

    /// Card fill and outline. Derived from `primary`, so they work in light and dark mode.
    static let surface = Color.primary.opacity(0.04)
    static let hairline = Color.primary.opacity(0.08)
    /// Behind a row under the pointer.
    static let hover = Color.primary.opacity(0.05)

    enum Typography {
        /// The one big number on Ringkasan.
        static let hero = Font.system(size: 34, weight: .semibold, design: .rounded)
        /// A page's key number, such as how much can be cleaned up.
        static let metric = Font.system(size: 26, weight: .semibold, design: .rounded)
        static let rowTitle = Font.body.weight(.medium)
    }

    enum Motion {
        /// A page switching between idle, scanning and results.
        static let page = Animation.smooth(duration: 0.28)
        /// Small changes: a row opening, a number rolling, a highlight fading.
        static let quick = Animation.smooth(duration: 0.18)
    }
}
