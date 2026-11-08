import Foundation

/// The Photos library, and the folders the Music and TV apps keep their media in.
///
/// macOS guards each of them with a permission of its own, apart from Desktop, Documents and Downloads, so reading them
/// without Full Disk Access makes macOS ask the user. Scans of the whole home folder leave them out until Havus has
/// Full Disk Access, and say they couldn't be read.
public struct MediaLibraries: Sendable, Hashable {
    /// Under the home folder: where Music (iTunes before it) and TV keep their libraries and media.
    static let mediaFolders = [["Music", "Music"], ["Music", "iTunes"], ["Movies", "TV"]]

    public let home: URL
    private let homeComponents: [String]

    public init(home: URL = .homeDirectory) {
        self.home = home
        homeComponents = home.standardizedFileURL.pathComponents
    }

    /// Whether `url` is one of them or inside one. Looks at the path only, never at the disk: even reading a size
    /// inside one would make macOS ask.
    public func contain(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        // A Photos library can sit anywhere, such as on an external drive.
        if components.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) { return true }
        guard components.count > homeComponents.count, components.starts(with: homeComponents) else { return false }
        let relative = components.dropFirst(homeComponents.count)
        return Self.mediaFolders.contains { relative.starts(with: $0) }
    }
}
