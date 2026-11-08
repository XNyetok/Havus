import Foundation

/// What a problem report says about the Mac.
public enum MacInfo {
    /// The macOS version with its build, such as `macOS 27.2 (26B123)`.
    public static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            text += ".\(version.patchVersion)"
        }
        if let build = sysctlString("kern.osversion") {
            text += " (\(build))"
        }
        return text
    }

    /// Whether the Mac has Apple silicon, even when Havus runs under Rosetta.
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
