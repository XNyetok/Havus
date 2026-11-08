import Foundation

extension Bundle {
    /// Such as `0.4.0 (12)`: the build number tells a release apart from a build of the same version made elsewhere.
    var versionAndBuild: String? {
        guard let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        guard let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return version }
        return "\(version) (\(build))"
    }
}
