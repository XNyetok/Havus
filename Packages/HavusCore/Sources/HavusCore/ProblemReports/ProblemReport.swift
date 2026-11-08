import Foundation

/// Where the user sends a problem report: a new issue on GitHub, or an email for those without a GitHub account.
/// Havus only opens these links, with the details it knows filled in. The user reviews the report and sends it.
public enum ProblemReport {
    /// The address SECURITY.md gives too.
    public static let emailAddress = "debi@elysiumx.org"

    /// The bug report form (`.github/ISSUE_TEMPLATE/bug_report.yml`). GitHub fills in a form field from the query
    /// item named after the field's `id`, and leaves out the ones that are `nil`.
    public static func issueURL(title: String?, version: String?, macOS: String?, whatHappened: String?) -> URL? {
        guard var components = URLComponents(string: "https://github.com/XNyetok/Havus/issues/new") else { return nil }
        let fields: [(name: String, value: String?)] = [
            ("template", "bug_report.yml"), ("title", title), ("version", version), ("macos", macOS),
            ("what-happened", whatHappened),
        ]
        components.queryItems = fields.compactMap { field in
            field.value.map { URLQueryItem(name: field.name, value: $0) }
        }
        return url(components)
    }

    public static func emailURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body),
        ]
        return url(components)
    }

    /// `URLComponents` leaves `+` alone in a query, where it would come out as a space.
    private static func url(_ components: URLComponents) -> URL? {
        var components = components
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
