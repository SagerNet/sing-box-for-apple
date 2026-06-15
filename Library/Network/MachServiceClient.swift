#if os(macOS) || JAILBREAK
    import Foundation
    import os

    public class MachServiceClient {
        private let machServiceName: String
        private let remoteInterface: NSXPCInterface
        private let logger: Logger
        private var connection: NSXPCConnection?
        private let connectionLock = NSLock()

        init(machServiceName: String, remoteInterface: NSXPCInterface, logger: Logger) {
            self.machServiceName = machServiceName
            self.remoteInterface = remoteInterface
            self.logger = logger
        }

        private func currentConnection() -> NSXPCConnection {
            connectionLock.lock()
            defer { connectionLock.unlock() }
            if let connection {
                return connection
            }
            let newConnection = XPCMachServiceBridge.makeConnection(machServiceName: machServiceName)
            newConnection.remoteObjectInterface = remoteInterface
            newConnection.invalidationHandler = { [weak self] in
                guard let self else { return }
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
            }
            newConnection.resume()
            connection = newConnection
            return newConnection
        }

        func callOptional<T>(
            _ operation: String,
            timeout: DispatchTimeInterval = .seconds(5),
            _ body: (AnyObject, @escaping (T?, NSError?) -> Void) -> Void
        ) throws -> T? {
            let semaphore = DispatchSemaphore(value: 0)
            var result: T?
            var resultError: NSError?
            let proxy = currentConnection().remoteObjectProxyWithErrorHandler { [logger] error in
                logger.error("\(operation, privacy: .public) XPC error: \(error.localizedDescription, privacy: .public)")
                resultError = error as NSError
                semaphore.signal()
            }
            body(proxy as AnyObject) { value, error in
                result = value
                resultError = error
                semaphore.signal()
            }
            let deadline: DispatchTime = timeout == .never ? .distantFuture : .now() + timeout
            if semaphore.wait(timeout: deadline) == .timedOut {
                logger.error("\(operation, privacy: .public): timeout")
                throw Self.error("\(operation) request timeout")
            }
            if let resultError {
                logger.error("\(operation, privacy: .public) error: \(resultError.localizedDescription, privacy: .public)")
                throw resultError
            }
            return result
        }

        func call<T>(
            _ operation: String,
            timeout: DispatchTimeInterval = .seconds(5),
            _ body: (AnyObject, @escaping (T?, NSError?) -> Void) -> Void
        ) throws -> T {
            guard let value: T = try callOptional(operation, timeout: timeout, body) else {
                throw Self.error("\(operation) returned nil")
            }
            return value
        }

        func callVoid(
            _ operation: String,
            timeout: DispatchTimeInterval = .seconds(5),
            _ body: (AnyObject, @escaping (NSError?) -> Void) -> Void
        ) throws {
            let semaphore = DispatchSemaphore(value: 0)
            var resultError: NSError?
            let proxy = currentConnection().remoteObjectProxyWithErrorHandler { [logger] error in
                logger.error("\(operation, privacy: .public) XPC error: \(error.localizedDescription, privacy: .public)")
                resultError = error as NSError
                semaphore.signal()
            }
            body(proxy as AnyObject) { error in
                resultError = error
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                logger.error("\(operation, privacy: .public): timeout")
                throw Self.error("\(operation) request timeout")
            }
            if let resultError {
                logger.error("\(operation, privacy: .public) error: \(resultError.localizedDescription, privacy: .public)")
                throw resultError
            }
        }

        static func error(_ message: String) -> NSError {
            NSError(domain: "MachServiceClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
#endif
