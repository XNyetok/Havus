import Foundation
import Testing

@testable import HavusCore

struct MediaLibrariesTests {
    @Test func knowsThePhotosLibraryAndTheMusicAndTVFolders() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let libraries = MediaLibraries(home: home)
        let inHome = { (path: String) in libraries.contain(home.appending(path: path)) }

        #expect(inHome("Pictures/Photos Library.photoslibrary"))
        #expect(inHome("Pictures/Photos Library.photoslibrary/originals/A/a.heic"))
        #expect(libraries.contain(URL(filePath: "/Volumes/Backup/Old.photoslibrary/database/Photos.sqlite")))
        #expect(inHome("Music/Music"))
        #expect(inHome("Music/Music/Media.localized/song.m4a"))
        #expect(inHome("Music/iTunes/iTunes Library.itl"))
        #expect(inHome("Movies/TV/Media.localized/show.mp4"))

        #expect(!inHome("Music"))
        #expect(!inHome("Music/mix.mp3"))
        #expect(!inHome("Movies/TV Shows/episode.mp4"))
        #expect(!inHome("Documents/Music/Music/song.mp3"))
        #expect(!libraries.contain(URL(filePath: "/Users/other/Music/Music/song.m4a")))
    }

    @Test func theDiskMapLeavesThemUnopenedWhenAsked() throws {
        let home = try TemporaryHome()
        try home.makeFile("Pictures/Photos Library.photoslibrary/originals/a.jpg", bytes: 300_000)
        try home.makeFile("Music/Music/Media.localized/song.m4a", bytes: 300_000)
        try home.makeFile("Music/mix.mp3", bytes: 300_000)
        let skipping = DiskUsageScanner(
            detailThreshold: 200_000, maximumListed: 3, skipping: MediaLibraries(home: home.url))

        let pictures = skipping.scan(home.url.appending(path: "Pictures"))
        let library = try #require(pictures.children?.first)
        #expect(library.bytes == 0)
        #expect(!library.isComplete)
        #expect(!pictures.isComplete)

        let music = skipping.scan(home.url.appending(path: "Music"))
        let musicLibrary = try #require(music.children?.first { $0.name == "Music" })
        let mix = try #require(music.children?.first { $0.name == "mix.mp3" })
        #expect(musicLibrary.bytes == 0)
        #expect(!musicLibrary.isComplete)
        #expect(mix.bytes >= 300_000)

        // Opening a library on its own leaves it closed too.
        let opened = skipping.scan(home.url.appending(path: "Music/Music"))
        #expect(opened.bytes == 0)
        #expect(!opened.isComplete)

        // Without being asked, the scanner counts everything.
        let everything = DiskUsageScanner(detailThreshold: 200_000, maximumListed: 3)
            .scan(home.url.appending(path: "Music"))
        #expect(everything.isComplete)
        #expect(everything.bytes >= 600_000)
    }

    @Test func largeFilesLeavesThemOutWhenAsked() throws {
        let home = try TemporaryHome()
        try home.makeFile("Music/Music/Media.localized/song.m4a", bytes: 3_000_000)
        try home.makeFile("Movies/TV/Media.localized/show.mp4", bytes: 3_000_000)
        try home.makeFile("Movies/trip.mov", bytes: 3_000_000)
        let criteria = LargeFileFinder.Criteria(minimumSize: 2_000_000)

        let skipping = LargeFileFinder(home: home.url, usesSpotlight: false, skipping: MediaLibraries(home: home.url))
            .find(criteria)
        let everything = LargeFileFinder(home: home.url, usesSpotlight: false).find(criteria)

        #expect(skipping.map(\.url.lastPathComponent) == ["trip.mov"])
        #expect(Set(everything.map(\.url.lastPathComponent)) == ["song.m4a", "show.mp4", "trip.mov"])
    }
}
