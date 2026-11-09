import Darwin
import Foundation
import Testing

@testable import HavusCore

struct DiskUsageSnapshotTests {
    /// Small numbers, so a few test files make folders with and without a list, and items folded into the rest.
    private let scanner = DiskUsageScanner(detailThreshold: 200_000, maximumListed: 4)

    @Test func loadsTheMapAsItWasSaved() throws {
        let home = try TemporaryHome()
        try home.makeFile("Movies/film.mov", bytes: 400_000)
        try home.makeFile("Movies/clips/clip.mov", bytes: 100_000)
        for index in 0..<6 {
            try home.makeFile("Downloads/file\(index).bin", bytes: 100_000)
        }
        try home.makeApp("Applications", name: "Tool", bundleID: "com.example.tool")
        try home.makeFile("Applications/Tool.app/Contents/MacOS/Tool", bytes: 300_000)
        let locked = try home.makeFolder("Locked")
        try home.makeFile("Locked/secret.bin")
        try home.lock(locked)
        let folder = realPath(home.url)
        let root = scanner.scan(folder)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let file = home.url.appending(path: "Saved/DiskMap.plist")

        try DiskUsageSnapshot(root: root, date: date, hadFullDiskAccess: false).save(to: file)
        let loaded = try #require(DiskUsageSnapshot.load(from: file, of: folder))

        #expect(isSame(loaded.root, root))
        #expect(loaded.date == date)
        #expect(!loaded.hadFullDiskAccess)
        // The map has what the round trip must keep apart: no list, an empty list, and items folded into the rest.
        let children = try #require(root.children)
        let movies = try #require(children.first { $0.name == "Movies" })
        #expect(try #require(movies.children?.first { $0.name == "clips" }).children == nil)
        #expect(try #require(children.first { $0.name == "Locked" }).children?.isEmpty == true)
        #expect(try #require(children.first { $0.name == "Downloads" }).otherItems.count == 2)
        #expect(try #require(children.first { $0.name == "Applications" }).children?.first?.kind == .package)
    }

    /// Everything the two items hold, down to their children's children. A list of none isn't the same as no list.
    private func isSame(_ first: DiskUsageItem, _ second: DiskUsageItem) -> Bool {
        first.url == second.url && first.kind == second.kind && first.bytes == second.bytes
            && first.isComplete == second.isComplete && first.otherItems == second.otherItems
            && first.children?.count == second.children?.count
            && zip(first.children ?? [], second.children ?? []).allSatisfy(isSame)
    }

    /// The temporary folder is behind a link (`/var` → `/private/var`), and a scan finds what's inside it under the real
    /// path. A home folder has no such link, so the tests scan the real path too.
    private func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return url }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
    }

    @Test func ignoresAMapOfAnotherFolder() throws {
        let home = try TemporaryHome()
        try home.makeFile("Movies/film.mov", bytes: 400_000)
        let file = home.url.appending(path: "DiskMap.plist")

        let movies = scanner.scan(home.url.appending(path: "Movies"))
        try DiskUsageSnapshot(root: movies, date: .now, hadFullDiskAccess: true).save(to: file)

        #expect(DiskUsageSnapshot.load(from: file, of: home.url) == nil)
    }

    @Test func ignoresAFileItCantRead() throws {
        let home = try TemporaryHome()
        let garbage = try home.makeFile("DiskMap.plist", bytes: 1_000)

        #expect(DiskUsageSnapshot.load(from: home.url.appending(path: "Missing.plist"), of: home.url) == nil)
        #expect(DiskUsageSnapshot.load(from: garbage, of: home.url) == nil)
    }

    @Test func ignoresAMapInAnotherFormat() throws {
        let home = try TemporaryHome()
        func map(format: Int) -> [String: Any] {
            [
                "format": format, "folder": home.url.standardizedFileURL.path, "date": Date.now,
                "hadFullDiskAccess": true, "root": ["n": home.url.lastPathComponent, "k": 0, "b": 0, "l": [Any]()],
            ]
        }
        let current = try home.makePlist("Current.plist", map(format: 1))
        let other = try home.makePlist("Other.plist", map(format: 2))

        #expect(DiskUsageSnapshot.load(from: current, of: home.url) != nil)
        #expect(DiskUsageSnapshot.load(from: other, of: home.url) == nil)
    }
}
