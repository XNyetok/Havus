import Foundation
import Testing

@testable import HavusCore

struct AppCatalogTests {
    @Test func readsAppsOneFolderDeep() throws {
        let home = try TemporaryHome()
        let applications = try home.makeFolder("Applications")
        try home.makeApp("Applications", name: "Example", bundleID: "com.example.Example", version: "1.2")
        try home.makeApp("Applications/Suite", name: "Nested", bundleID: "com.example.Nested")
        try home.makeApp("Applications/Suite/Deeper", name: "TooDeep", bundleID: "com.example.TooDeep")

        let apps = AppCatalog(searchRoots: [applications]).installedApps()

        #expect(apps.map(\.name) == ["Example", "Nested"])
        #expect(apps.first?.bundleIdentifier == "com.example.Example")
        #expect(apps.first?.version == "1.2")
    }

    @Test func skipsInvalidAndSymlinkedBundles() throws {
        let home = try TemporaryHome()
        let applications = try home.makeFolder("Applications")
        let real = try home.makeApp("Elsewhere", name: "Real", bundleID: "com.example.Real")
        try home.makeApp("Applications", name: "NoIdentifier", bundleID: nil)
        try FileManager.default.createSymbolicLink(
            at: applications.appending(path: "Linked.app"), withDestinationURL: real)

        #expect(AppCatalog(searchRoots: [applications]).installedApps().isEmpty)
    }
}

struct LeftoverFinderTests {
    private let app = InstalledApp(
        url: URL(filePath: "/Applications/Example.app"), name: "Example",
        bundleIdentifier: "com.example.Example", bundleName: "Example", version: "1.0")
    /// ByHost preferences files carry the Mac's hardware UUID in their name.
    private let hostUUID = "12345678-ABCD-4EF0-9876-543210FEDCBA"

    @Test func findsDataNamedAfterTheBundleIdentifier() throws {
        let home = try TemporaryHome()
        try home.makeFile("Library/Application Support/com.example.Example/data.db")
        try home.makeFile("Library/Caches/com.example.Example/cache")
        try home.makeFile("Library/Preferences/com.example.Example.plist")
        try home.makeFile("Library/Preferences/ByHost/com.example.Example.\(hostUUID).plist")
        try home.makeFile("Library/Containers/com.example.Example/Data/state")
        try home.makeFile("Library/Group Containers/ABCDE12345.com.example.Example/shared")
        try home.makeFile("Library/Saved Application State/com.example.Example.savedState/data")
        try home.makeFile("Library/HTTPStorages/com.example.Example.binarycookies")
        try home.makeFile("Library/Application Support/com.other.App/data.db")

        let found = LeftoverFinder(home: home.url).leftovers(for: app)

        #expect(
            Set(found.map { "\($0.kind.rawValue)/\($0.url.lastPathComponent)" }) == [
                "applicationSupport/com.example.Example",
                "caches/com.example.Example",
                "preferences/com.example.Example.plist",
                "preferences/com.example.Example.\(hostUUID).plist",
                "containers/com.example.Example",
                "groupContainers/ABCDE12345.com.example.Example",
                "savedState/com.example.Example.savedState",
                "httpStorage/com.example.Example.binarycookies",
            ])
        #expect(found.allSatisfy { $0.match == .bundleIdentifier && $0.size > 0 })
    }

    @Test func flagsDataThatMayBelongToAnotherApp() throws {
        let home = try TemporaryHome()
        // Like the settings of Google Chrome for Testing (com.google.chrome.for.testing) next to Google Chrome's.
        try home.makeFile("Library/Preferences/com.example.example.for.testing.plist")
        try home.makeFile("Library/Preferences/ByHost/com.example.Example.Helper.\(hostUUID).plist")
        try home.makeFile("Library/Containers/com.example.Example.Widget/Data/state")

        let found = LeftoverFinder(home: home.url).leftovers(for: app)

        #expect(
            Set(found.map(\.url.lastPathComponent)) == [
                "com.example.example.for.testing.plist",
                "com.example.Example.Helper.\(hostUUID).plist",
                "com.example.Example.Widget",
            ])
        #expect(found.allSatisfy { $0.match == .bundleIdentifierPrefix })
    }

    @Test func flagsLeftoversItCantRead() throws {
        let home = try TemporaryHome()
        let support = try home.makeFolder("Library/Application Support/com.example.Example")
        try home.makeFile("Library/Application Support/com.example.Example/profile.db", bytes: 100_000)
        try home.makeFile("Library/Caches/com.example.Example/cache")
        try home.lock(support)

        let found = LeftoverFinder(home: home.url).leftovers(for: app)
        let unreadable = try #require(found.first { $0.kind == .applicationSupport })
        let readable = try #require(found.first { $0.kind == .caches })

        #expect(!unreadable.isFullyReadable)
        #expect(unreadable.size == 0)
        #expect(readable.isFullyReadable)
        #expect(readable.size > 0)
    }

    @Test func leavesDataOfMoreSpecificInstalledApps() throws {
        let home = try TemporaryHome()
        try home.makeFile("Library/Application Support/com.example.Example.Beta/data")

        let found = LeftoverFinder(home: home.url)
            .leftovers(for: app, otherBundleIdentifiers: ["com.example.Example.Beta"])

        #expect(found.isEmpty)
    }

    @Test func matchesByNameOnlyWhereAppsDoThatAndFlagsIt() throws {
        let home = try TemporaryHome()
        try home.makeFile("Library/Application Support/Example/data")
        try home.makeFile("Library/Preferences/Example/notes")

        let found = LeftoverFinder(home: home.url).leftovers(for: app)

        #expect(found.map(\.kind) == [.applicationSupport])
        #expect(found.map(\.match) == [.appName])
    }

    @Test func neverMatchesAppleAppsByName() throws {
        let home = try TemporaryHome()
        try home.makeFile("Library/Application Support/Mail/data")
        let mail = InstalledApp(
            url: URL(filePath: "/Applications/Mail.app"), name: "Mail",
            bundleIdentifier: "com.apple.mail", bundleName: "Mail", version: nil)

        #expect(LeftoverFinder(home: home.url).leftovers(for: mail).isEmpty)
    }
}
