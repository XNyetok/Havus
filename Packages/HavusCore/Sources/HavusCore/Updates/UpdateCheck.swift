import Foundation

/// Asks GitHub for the newest Havus version. This is the only network request Havus makes, and it runs only
/// when the user checks for a new version, or turned on the daily check themselves (see docs/architecture.md).
///
/// The request carries nothing about the user or their Mac: no cookies, no cache, and fixed `User-Agent` and
/// `Accept-Language` headers instead of the default ones, which would name the macOS version and the user's
/// languages. Of GitHub's answer only the tag is read; the release notes and everything else are ignored.
public enum UpdateCheck {
    /// GitHub's "latest release" of Havus: the newest published release, never a draft or a prerelease.
    // swift-format-ignore: NeverForceUnwrap
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/XNyetok/Havus/releases/latest")!

    /// The automatic check runs at most once per interval: once a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    public enum Failure: Error, Equatable {
        /// GitHub answered with an error, e.g. 403 when its rate limit is reached, or 404 before the first release.
        case httpStatus(Int)
        /// The answer isn't a published release with a `vX.Y.Z` tag.
        case unreadableRelease
    }

    /// Whether the automatic check is due, given when the last one ran.
    public static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        // A clock that was set back leaves the last check in the future; don't wait for it to come around.
        return elapsed >= interval || elapsed < 0
    }

    /// Fetches the version of the newest published release.
    public static func latestVersion(from url: URL = latestReleaseURL) async throws -> AppVersion {
        let (data, response) = try await session.data(for: request(for: url))
        return try latestVersion(from: data, response: response)
    }

    public static func request(for url: URL = latestReleaseURL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        // GitHub requires a User-Agent; this one says only which app is asking.
        request.setValue("Havus", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    /// Reads GitHub's answer to `request(for:)`.
    public static func latestVersion(from data: Data, response: URLResponse) throws -> AppVersion {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else { throw Failure.httpStatus(statusCode) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(GitHubRelease.self, from: data),
            release.draft != true, release.prerelease != true,
            let version = AppVersion(release.tagName)
        else { throw Failure.unreadableRelease }
        return version
    }

    /// Where Havus links for `version`: the release on the changelog at havus.web.id, anchored by its tag (`#v0.3.0`).
    /// The site has the changelog in English too, under /en/, so the link follows the language Havus runs in,
    /// `language` (such as `en` or `id`, from `Bundle.main.preferredLocalizations`). Any other language gets the
    /// Indonesian page, just as the app falls back to Indonesian.
    public static func changelogURL(for version: AppVersion, language: String?) -> URL? {
        var components = URLComponents(
            string: Website.isEnglish(language)
                ? "https://havus.web.id/en/changelog/" : "https://havus.web.id/changelog/")
        components?.fragment = "v\(version)"
        return components?.url
    }

    /// Keeps nothing between checks: no cookies, no cache, no credentials.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool?
        let prerelease: Bool?
    }
}
