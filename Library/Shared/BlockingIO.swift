import Foundation

public enum BlockingIO {
    private static let queue = DispatchQueue(
        label: "io.nekohasekai.sing-box.blocking-io",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                #if DEBUG
                    precondition(!Thread.isMainThread, "BlockingIO operation must not run on the main thread")
                #endif
                do {
                    try continuation.resume(returning: operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func run<T: Sendable>(_ operation: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                #if DEBUG
                    precondition(!Thread.isMainThread, "BlockingIO operation must not run on the main thread")
                #endif
                continuation.resume(returning: operation())
            }
        }
    }
}
