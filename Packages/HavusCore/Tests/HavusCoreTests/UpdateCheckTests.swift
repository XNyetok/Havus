import Foundation
import Testing

@testable import HavusCore

struct AppVersionTests {
    @Test func readsVersionsAndReleaseTags() {
        #expect(AppVersion("0.1.0") == AppVersion(major: 0, minor: 1, patch: 0))
        #expect(AppVersion("v0.2.0") == AppVersion(major: 0, minor: 2, patch: 0))
        #expect(AppVersion("v12.34.56")?.description == "12.34.56")
    }

    @Test(arguments: [
        "", "v", "1", "1.2", "1.2.3.4", "1..3", ".1.2", "1.2.", "V1.2.3", "vv1.2.3", " 1.2.3", "1.2.3 ",
        "1.2.3-beta", "1.2.3+4", "-1.2.3", "+1.2.3", "1.2.x", "１.2.3", "1.2.٣", "1234567890.0.0",
    ])
    func rejectsAnythingButXYZ(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesNumberByNumber() throws {
        let versions = try ["0.1.9", "0.1.10", "0.2.0", "0.10.0", "1.0.0"].map { try #require(AppVersion($0)) }

        #expect(versions == versions.sorted())
        #expect(AppVersion("v0.2.0") == AppVersion("0.2.0"))
        #expect(try #require(AppVersion("0.1.0")) < #require(AppVersion("0.1.1")))
    }
}

struct UpdateCheckTests {
    @Test func linksToTheChangelogInTheLanguageHavusRunsIn() throws {
        let version = try #require(AppVersion("0.3.0"))
        let link = { (language: String?) in UpdateCheck.changelogURL(for: version, language: language)?.absoluteString }

        #expect(link("en") == "https://havus.web.id/en/changelog/#v0.3.0")
        #expect(link("en-GB") == "https://havus.web.id/en/changelog/#v0.3.0")
        #expect(link("id") == "https://havus.web.id/changelog/#v0.3.0")
        // Languages the site doesn't have get the Indonesian page, like the app falls back to Indonesian.
        #expect(link("de") == "https://havus.web.id/changelog/#v0.3.0")
        #expect(link(nil) == "https://havus.web.id/changelog/#v0.3.0")
    }

    @Test func linksToTheWebsiteInTheLanguageHavusRunsIn() {
        let link = { (language: String?) in Website.home(language: language)?.absoluteString }

        #expect(link("en") == "https://havus.web.id/en/")
        #expect(link("en-GB") == "https://havus.web.id/en/")
        #expect(link("id") == "https://havus.web.id/")
        #expect(link("de") == "https://havus.web.id/")
        #expect(link(nil) == "https://havus.web.id/")
    }

    private func response(_ statusCode: Int) throws -> HTTPURLResponse {
        try #require(
            HTTPURLResponse(
                url: UpdateCheck.latestReleaseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }

    private func release(tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        // Trimmed from a real answer: everything but these fields is ignored.
        Data(
            """
            {"tag_name": "\(tag)", "name": "Havus \(tag)", "draft": \(draft), "prerelease": \(prerelease),
             "html_url": "https://github.com/XNyetok/Havus/releases/tag/\(tag)", "body": "## Bahasa Indonesia",
             "assets": [{"name": "Havus-0.2.0.zip", "size": 651737}]}
            """.utf8)
    }

    @Test func readsTheLatestRelease() throws {
        let version = try UpdateCheck.latestVersion(from: release(tag: "v0.2.0"), response: response(200))

        #expect(version == AppVersion(major: 0, minor: 2, patch: 0))
    }

    @Test func rejectsDraftsPrereleasesAndOtherTags() throws {
        for data in [
            release(tag: "v0.2.0", draft: true),
            release(tag: "v0.2.0", prerelease: true),
            release(tag: "v0.2.0-beta"),
            release(tag: "nightly"),
            Data(#"{"message": "Not Found"}"#.utf8),
            Data("<html>".utf8),
        ] {
            #expect(throws: UpdateCheck.Failure.unreadableRelease) {
                try UpdateCheck.latestVersion(from: data, response: response(200))
            }
        }
    }

    @Test func reportsHTTPErrors() throws {
        // 403: GitHub's rate limit. 404: no published release yet.
        for statusCode in [403, 404, 500] {
            #expect(throws: UpdateCheck.Failure.httpStatus(statusCode)) {
                try UpdateCheck.latestVersion(from: release(tag: "v0.2.0"), response: response(statusCode))
            }
        }
    }

    @Test func requestSaysNothingAboutTheMac() {
        let request = UpdateCheck.request()

        #expect(request.url?.absoluteString == "https://api.github.com/repos/XNyetok/Havus/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(!request.httpShouldHandleCookies)
        // Replace the defaults, which would name the macOS version and the user's languages.
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Havus")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
    }

    @Test func automaticCheckRunsAtMostOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hour: TimeInterval = 60 * 60

        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now - 23 * hour, now: now))
        #expect(UpdateCheck.isDue(lastCheck: now - 24 * hour, now: now))
        // The clock was set back: don't wait days for the last check to come around.
        #expect(UpdateCheck.isDue(lastCheck: now + 72 * hour, now: now))
    }
}
