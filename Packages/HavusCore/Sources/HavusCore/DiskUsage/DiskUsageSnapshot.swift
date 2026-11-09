import Foundation

/// A disk map kept between launches, so Peta Disk can show the last one right away instead of scanning again.
///
/// The file holds what the map shows, the names and sizes of the items in it, and nothing else. A file that can't be
/// read, one in another format, or a map of another folder counts as no map at all.
public struct DiskUsageSnapshot: Sendable {
    /// The folder that was scanned, with everything the scan kept inside it.
    public let root: DiskUsageItem
    /// When the scan started. Changes since then may be missing from the map.
    public let date: Date
    /// Whether Full Disk Access was on during the scan. Without it, macOS kept some folders closed.
    public let hadFullDiskAccess: Bool

    public init(root: DiskUsageItem, date: Date, hadFullDiskAccess: Bool) {
        self.root = root
        self.date = date
        self.hadFullDiskAccess = hadFullDiskAccess
    }

    /// Writes the map to `file` in one step, replacing the one there, and creates the folder that holds it.
    public func save(to file: URL) throws {
        let stored = Stored(
            format: Stored.currentFormat, folder: Self.path(of: root.url), date: date,
            hadFullDiskAccess: hadFullDiskAccess, root: Node(root))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(stored)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// The map in `file`, if it's a map of `folder`. `nil` when there's none, or none Havus can use.
    public static func load(from file: URL, of folder: URL) -> DiskUsageSnapshot? {
        guard let data = try? Data(contentsOf: file),
            let stored = try? PropertyListDecoder().decode(Stored.self, from: data),
            stored.format == Stored.currentFormat, stored.folder == path(of: folder)
        else { return nil }
        return DiskUsageSnapshot(
            root: stored.root.item(at: folder), date: stored.date, hadFullDiskAccess: stored.hadFullDiskAccess)
    }

    private static func path(of url: URL) -> String {
        url.standardizedFileURL.path
    }
}

/// The file's contents. A change to ``Node`` needs a new ``currentFormat``, so older files are left alone.
private struct Stored: Codable {
    static let currentFormat = 1

    let format: Int
    /// The scanned folder's path.
    let folder: String
    let date: Date
    let hadFullDiskAccess: Bool
    let root: Node
}

/// One item on the map. Its place comes from the folder that holds it, so only its name is kept, and the keys are
/// short: a home folder's map can hold tens of thousands of items.
private struct Node: Codable {
    let name: String
    let kind: Kind
    let bytes: Int64
    let isComplete: Bool
    /// `nil` for a folder the scan kept no list for, which isn't the same as an empty list.
    let children: [Node]?
    let otherCount: Int
    let otherBytes: Int64

    /// Its own numbers, so the file doesn't change with ``DiskUsageItem/Kind``.
    enum Kind: Int, Codable {
        case folder, package, file

        init(_ kind: DiskUsageItem.Kind) {
            self =
                switch kind {
                case .folder: .folder
                case .package: .package
                case .file: .file
                }
        }

        var itemKind: DiskUsageItem.Kind {
            switch self {
            case .folder: .folder
            case .package: .package
            case .file: .file
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name = "n", kind = "k", bytes = "b", isComplete = "c", children = "l", otherCount = "oc"
        case otherBytes = "ob"
    }

    init(_ item: DiskUsageItem) {
        name = item.name
        kind = Kind(item.kind)
        bytes = item.bytes
        isComplete = item.isComplete
        children = item.children?.map(Node.init)
        otherCount = item.otherItems.count
        otherBytes = item.otherItems.bytes
    }

    /// The item, at `url`. Its children's URLs are built the way a scan finds them: a folder's ends in a slash.
    func item(at url: URL) -> DiskUsageItem {
        DiskUsageItem(
            url: url, kind: kind.itemKind, bytes: bytes, isComplete: isComplete,
            children: children?.map { child in
                let hint: URL.DirectoryHint = child.kind == .file ? .notDirectory : .isDirectory
                return child.item(at: url.appending(path: child.name, directoryHint: hint))
            },
            otherItems: DiskUsageItem.OtherItems(count: otherCount, bytes: otherBytes))
    }

    // Values most items share are left out of the file.

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(Kind.self, forKey: .kind)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
        children = try container.decodeIfPresent([Node].self, forKey: .children)
        otherCount = try container.decodeIfPresent(Int.self, forKey: .otherCount) ?? 0
        otherBytes = try container.decodeIfPresent(Int64.self, forKey: .otherBytes) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(bytes, forKey: .bytes)
        if !isComplete { try container.encode(isComplete, forKey: .isComplete) }
        try container.encodeIfPresent(children, forKey: .children)
        if otherCount > 0 {
            try container.encode(otherCount, forKey: .otherCount)
            try container.encode(otherBytes, forKey: .otherBytes)
        }
    }
}
