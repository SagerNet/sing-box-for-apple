#if os(macOS)
    import Foundation
    import os

    private let logger = Logger(category: "RootHelperXPC")

    @objc public class ConnectionOwnerResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var userId: Int32
        @objc public var userName: String
        @objc public var processPath: String

        public init(userId: Int32, userName: String, processPath: String) {
            self.userId = userId
            self.userName = userName
            self.processPath = processPath
        }

        public required init?(coder: NSCoder) {
            userId = coder.decodeInt32(forKey: "userId")
            userName = coder.decodeObject(of: NSString.self, forKey: "userName") as? String ?? ""
            processPath = coder.decodeObject(of: NSString.self, forKey: "processPath") as? String ?? ""
        }

        public func encode(with coder: NSCoder) {
            coder.encode(userId, forKey: "userId")
            coder.encode(userName as NSString, forKey: "userName")
            coder.encode(processPath as NSString, forKey: "processPath")
        }
    }

    @objc public protocol RootHelperProtocol {
        func findConnectionOwner(
            ipProtocol: Int32,
            sourceAddress: String,
            sourcePort: Int32,
            destinationAddress: String,
            destinationPort: Int32,
            reply: @escaping (ConnectionOwnerResult?, NSError?) -> Void
        )

        func getWorkingDirectorySize(reply: @escaping (Int64, NSError?) -> Void)
        func cleanWorkingDirectory(reply: @escaping (NSError?) -> Void)
        func getVersion(reply: @escaping (String) -> Void)
    }

    public enum RootHelperXPC {
        public static func configureInterface(_ interface: NSXPCInterface) {
            let resultClasses = NSSet(array: [ConnectionOwnerResult.self, NSString.self]) as! Set<AnyHashable>
            interface.setClasses(
                resultClasses,
                for: #selector(RootHelperProtocol.findConnectionOwner(ipProtocol:sourceAddress:sourcePort:destinationAddress:destinationPort:reply:)),
                argumentIndex: 0,
                ofReply: true
            )
        }
    }

    public class RootHelperClient {
        public static let shared = RootHelperClient()

        private var connection: NSXPCConnection?
        private let connectionLock = NSLock()

        private init() {}

        private func getConnection() -> NSXPCConnection {
            connectionLock.lock()
            defer { connectionLock.unlock() }

            if let existing = connection {
                return existing
            }

            let newConnection = NSXPCConnection(machServiceName: AppConfiguration.rootHelperMachService)

            let remoteInterface = NSXPCInterface(with: RootHelperProtocol.self)
            RootHelperXPC.configureInterface(remoteInterface)
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

        private func performXPCCall<T>(
            _ operation: String,
            call: (RootHelperProtocol, @escaping (T?, NSError?) -> Void) -> Void
        ) throws -> T {
            let semaphore = DispatchSemaphore(value: 0)
            var result: T?
            var resultError: NSError?

            let conn = getConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                logger.error("\(operation) XPC error: \(error.localizedDescription)")
                resultError = error as NSError
                semaphore.signal()
            }) as? RootHelperProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get RootHelper proxy",
                ])
            }

            call(proxy) { value, error in
                result = value
                resultError = error
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) request timeout",
                ])
                logger.error("\(operation): timeout")
                throw error
            }

            if let error = resultError {
                logger.error("\(operation) error: \(error.localizedDescription)")
                throw error
            }

            guard let value = result else {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) returned nil",
                ])
                throw error
            }

            return value
        }

        private func performXPCCallVoid(
            _ operation: String,
            call: (RootHelperProtocol, @escaping (NSError?) -> Void) -> Void
        ) throws {
            let semaphore = DispatchSemaphore(value: 0)
            var resultError: NSError?

            let conn = getConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                logger.error("\(operation) XPC error: \(error.localizedDescription)")
                resultError = error as NSError
                semaphore.signal()
            }) as? RootHelperProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get RootHelper proxy",
                ])
            }

            call(proxy) { error in
                resultError = error
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) request timeout",
                ])
                logger.error("\(operation): timeout")
                throw error
            }

            if let error = resultError {
                logger.error("\(operation) error: \(error.localizedDescription)")
                throw error
            }
        }

        public func findConnectionOwner(
            ipProtocol: Int32,
            sourceAddress: String,
            sourcePort: Int32,
            destinationAddress: String,
            destinationPort: Int32
        ) throws -> ConnectionOwnerResult {
            try performXPCCall("findConnectionOwner") { proxy, reply in
                proxy.findConnectionOwner(
                    ipProtocol: ipProtocol,
                    sourceAddress: sourceAddress,
                    sourcePort: sourcePort,
                    destinationAddress: destinationAddress,
                    destinationPort: destinationPort,
                    reply: reply
                )
            }
        }

        public func getWorkingDirectorySize() throws -> Int64 {
            try performXPCCall("getWorkingDirectorySize") { proxy, reply in
                proxy.getWorkingDirectorySize { size, error in
                    reply(size as Int64?, error)
                }
            }
        }

        public func cleanWorkingDirectory() throws {
            try performXPCCallVoid("cleanWorkingDirectory") { proxy, reply in
                proxy.cleanWorkingDirectory(reply: reply)
            }
        }

        public func getVersion() throws -> String {
            let semaphore = DispatchSemaphore(value: 0)
            var result: String?
            var resultError: NSError?

            let conn = getConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                logger.error("getVersion XPC error: \(error.localizedDescription)")
                resultError = error as NSError
                semaphore.signal()
            }) as? RootHelperProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get RootHelper proxy",
                ])
            }

            proxy.getVersion { version in
                result = version
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "getVersion request timeout",
                ])
                logger.error("getVersion: timeout")
                throw error
            }

            if let error = resultError {
                throw error
            }

            guard let value = result else {
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "getVersion returned nil",
                ])
            }

            return value
        }
    }
#endif
