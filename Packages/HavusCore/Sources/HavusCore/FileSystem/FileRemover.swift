import Foundation
import os

/// The only component in Havus that removes files. Every URL is checked by ``PathGuard`` first.
public struct FileRemover: Sendable {
    public enum Method: Sendable, Hashable {
        /// Default. The user can still restore the item from the Trash.
        case moveToTrash
        /// Only used for items that are already in the Trash.
        case deletePermanently
    }

    public enum Reason: Sendable, Hashable {
        case blocked(PathGuard.Reason)
        case notFound
        case permissionDenied
        case other(String)
    }

    public struct Failure: Sendable, Hashable {
        public let url: URL
        public let reason: Reason
    }

    public struct Report: Sendable {
        public internal(set) var removed: [URL] = []
        public internal(set) var failures: [Failure] = []
    }

    /// Performs the actual file system change. Injectable so tests never touch the real Trash.
    public typealias Operation = @Sendable (URL, Method) throws -> Void

    private let pathGuard: PathGuard
    private let operation: Operation

    public init(pathGuard: PathGuard, operation: @escaping Operation = FileRemover.fileManagerOperation) {
        self.pathGuard = pathGuard
        self.operation = operation
    }

    /// Blocking. Removes `urls` one by one; a failure never stops the rest. Every refusal and failure is logged, with
    /// the path as a hash.
    public func remove(_ urls: [URL], method: Method, allowedRoots: [URL]) -> Report {
        var report = Report()
        for url in urls {
            if Task.isCancelled { break }
            let path = url.path(percentEncoded: false)
            if case .denied(let reason) = pathGuard.check(url, allowedRoots: allowedRoots) {
                Log.removal.error(
                    "PathGuard refused \(path, privacy: .private(mask: .hash)): \(String(describing: reason), privacy: .public)"
                )
                report.failures.append(Failure(url: url, reason: .blocked(reason)))
                continue
            }
            do {
                try operation(url, method)
                report.removed.append(url)
            } catch {
                let error = error as NSError
                Log.removal.error(
                    "Couldn't remove \(path, privacy: .private(mask: .hash)): \(error.domain, privacy: .public) \(error.code)"
                )
                report.failures.append(Failure(url: url, reason: Self.reason(for: error)))
            }
        }
        return report
    }

    public static let fileManagerOperation: Operation = { url, method in
        switch method {
        case .moveToTrash:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case .deletePermanently:
            try FileManager.default.removeItem(at: url)
        }
    }

    static func reason(for error: any Error) -> Reason {
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError):
            return .notFound
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError), (NSCocoaErrorDomain, NSFileReadNoPermissionError),
            (NSPOSIXErrorDomain, Int(EPERM)), (NSPOSIXErrorDomain, Int(EACCES)):
            return .permissionDenied
        default:
            return .other(error.localizedDescription)
        }
    }
}
