import Foundation

public extension URL {
    /// Best-effort security-scoped access:
    /// - If `startAccessingSecurityScopedResource()` succeeds, access is relinquished via `stop...` when `body` completes.
    /// - If it fails, `body` still runs (useful for non-security-scoped but otherwise accessible URLs).
    @discardableResult
    func withSecurityScopedAccess<T>(_ body: () throws -> T) rethrows -> T {
        let didStart = startAccessingSecurityScopedResource()
        defer {
            if didStart {
                stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    /// Async best-effort variant of `withSecurityScopedAccess`.
    @discardableResult
    func withSecurityScopedAccess<T>(_ body: () async throws -> T) async rethrows -> T {
        let didStart = startAccessingSecurityScopedResource()
        defer {
            if didStart {
                stopAccessingSecurityScopedResource()
            }
        }
        return try await body()
    }

    /// Required security-scoped access:
    /// - If `startAccessingSecurityScopedResource()` fails, throws `error` and does not run `body`.
    /// - Otherwise, guarantees a balanced `stop...` when `body` completes.
    @discardableResult
    func withRequiredSecurityScopedAccess<T>(
        or error: @autoclosure () -> any Error,
        _ body: () throws -> T
    ) throws -> T {
        guard startAccessingSecurityScopedResource() else {
            throw error()
        }
        defer { stopAccessingSecurityScopedResource() }
        return try body()
    }

    /// Async required variant of `withRequiredSecurityScopedAccess`.
    @discardableResult
    func withRequiredSecurityScopedAccess<T>(
        or error: @autoclosure () -> any Error,
        _ body: () async throws -> T
    ) async throws -> T {
        guard startAccessingSecurityScopedResource() else {
            throw error()
        }
        defer { stopAccessingSecurityScopedResource() }
        return try await body()
    }
}
