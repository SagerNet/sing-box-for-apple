import Foundation
import Libbox
import Network

public enum NWSocketError: Error {
    case connectionClosed
    case invalidLength(Int)
    case messageTooLarge(Int)
    case timeout(String)
}

extension NWSocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionClosed:
            "Connection closed"
        case let .invalidLength(length):
            "Invalid message length: \(length)"
        case let .messageTooLarge(length):
            "Message too large: \(length)"
        case let .timeout(phase):
            "Timed out: \(phase)"
        }
    }
}

private final class OneShot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}

public final class NWSocket {
    private let connection: NWConnection

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public func read(
        headerTimeout: TimeInterval = 0,
        bodyTimeout: TimeInterval = 60,
        maxMessageSize: Int = 32 * 1024 * 1024
    ) async throws -> Data {
        let lengthChunk = try await receiveExactly(count: 2, timeout: headerTimeout, phase: "read header")
        let length = Int(LibboxDecodeLengthChunk(lengthChunk))
        guard length >= 0 else {
            connection.cancel()
            throw NWSocketError.invalidLength(length)
        }
        guard length <= maxMessageSize else {
            connection.cancel()
            throw NWSocketError.messageTooLarge(length)
        }
        guard length > 0 else {
            return Data()
        }
        return try await receiveExactly(count: length, timeout: bodyTimeout, phase: "read body")
    }

    public func write(_ data: Data?, timeout: TimeInterval = 30) async throws {
        guard let data else {
            return
        }
        try await sendAndAwait(content: LibboxEncodeChunkedMessage(data), timeout: timeout, phase: "write")
    }

    public func send(_ data: Data?) {
        guard let data else {
            return
        }
        connection.send(content: LibboxEncodeChunkedMessage(data), completion: .idempotent)
    }

    public func cancel() {
        connection.cancel()
    }

    private func receiveExactly(count: Int, timeout: TimeInterval, phase: String) async throws -> Data {
        guard count > 0 else {
            return Data()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let oneShot = OneShot<Data>(continuation)
            let timeoutItem: DispatchWorkItem?
            if timeout > 0 {
                timeoutItem = DispatchWorkItem { [connection] in
                    if oneShot.resume(.failure(NWSocketError.timeout(phase))) {
                        connection.cancel()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem!)
            } else {
                timeoutItem = nil
            }

            connection.receive(minimumIncompleteLength: count, maximumLength: count) { content, _, isComplete, error in
                timeoutItem?.cancel()
                if let error {
                    oneShot.resume(.failure(error))
                    return
                }
                guard let content else {
                    oneShot.resume(.failure(NWSocketError.connectionClosed))
                    return
                }
                guard content.count == count else {
                    if isComplete {
                        oneShot.resume(.failure(NWSocketError.connectionClosed))
                    } else {
                        oneShot.resume(.failure(NWSocketError.invalidLength(content.count)))
                    }
                    return
                }
                oneShot.resume(.success(content))
            }
        }
    }

    private func sendAndAwait(content: Data?, timeout: TimeInterval, phase: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let oneShot = OneShot<Void>(continuation)
            let timeoutItem: DispatchWorkItem?
            if timeout > 0 {
                timeoutItem = DispatchWorkItem { [connection] in
                    if oneShot.resume(.failure(NWSocketError.timeout(phase))) {
                        connection.cancel()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem!)
            } else {
                timeoutItem = nil
            }

            connection.send(content: content, isComplete: false, completion: .contentProcessed { error in
                timeoutItem?.cancel()
                if let error {
                    oneShot.resume(.failure(error))
                } else {
                    oneShot.resume(.success(()))
                }
            })
        }
    }
}
