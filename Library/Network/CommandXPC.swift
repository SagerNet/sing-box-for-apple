#if os(macOS)
    import Foundation
    import Libbox
    import os

    private let logger = Logger(category: "CommandXPC")

    @objc public protocol CommandXPCProtocol {
        func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void)
        func registerUserServiceEndpoint(_ endpoint: NSXPCListenerEndpoint?, reply: @escaping (NSError?) -> Void)
        func extensionRequirements(reply: @escaping (Bool, Bool, NSError?) -> Void)
    }

    class CommandXPCService: NSObject, NSXPCListenerDelegate {
        let socketPath: String
        var commandServer: LibboxCommandServer?

        private enum ServiceReadyState {
            case pending
            case ready
            case failed(Error)
        }

        private let serviceReadyLock = NSLock()
        private var serviceReadyState = ServiceReadyState.pending
        private var serviceReadyContinuations: [CheckedContinuation<Void, Error>] = []
        private static let defaultNotReadyError = NSError(domain: "CommandXPC", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Command server not ready",
        ])

        init(socketPath: String) {
            self.socketPath = socketPath
        }

        func waitForServiceReady() async throws {
            serviceReadyLock.lock()
            switch serviceReadyState {
            case .ready:
                serviceReadyLock.unlock()
                return
            case let .failed(error):
                serviceReadyLock.unlock()
                throw error
            case .pending:
                return try await withCheckedThrowingContinuation { continuation in
                    serviceReadyContinuations.append(continuation)
                    serviceReadyLock.unlock()
                }
            }
        }

        func markServiceReady() {
            resolveServiceReady(.success(()))
        }

        func markServiceNotReady(_ error: Error? = nil) {
            resolveServiceReady(.failure(error ?? Self.defaultNotReadyError))
        }

        private func resolveServiceReady(_ result: Result<Void, Error>) {
            serviceReadyLock.lock()
            switch result {
            case .success:
                serviceReadyState = .ready
            case let .failure(error):
                serviceReadyState = .failed(error)
            }
            let continuations = serviceReadyContinuations
            serviceReadyContinuations.removeAll()
            serviceReadyLock.unlock()
            for continuation in continuations {
                continuation.resume(with: result)
            }
        }

        func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            let bundleID = AppConfiguration.packageName + ".standalone"
            let requirement = "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(AppConfiguration.teamID)\""
            do {
                try newConnection.setCodeSigningRequirement(requirement)
            } catch {
                logger.warning("Rejected XPC connection: \(error.localizedDescription)")
                return false
            }

            let exportedInterface = NSXPCInterface(with: CommandXPCProtocol.self)
            CommandXPC.configureInterface(exportedInterface)
            newConnection.exportedInterface = exportedInterface
            newConnection.exportedObject = CommandXPCHandler(service: self)
            newConnection.resume()
            return true
        }
    }

    private class CommandXPCHandler: NSObject, CommandXPCProtocol {
        private let service: CommandXPCService

        init(service: CommandXPCService) {
            self.service = service
        }

        func connectToCommandServer(reply: @escaping (FileHandle?, NSError?) -> Void) {
            do {
                let handle = try connectToUnixSocket(path: service.socketPath)
                reply(handle, nil)
            } catch {
                reply(nil, error as NSError)
            }
        }

        func registerUserServiceEndpoint(_ endpoint: NSXPCListenerEndpoint?, reply: @escaping (NSError?) -> Void) {
            if let endpoint {
                UserServiceEndpointRegistry.shared.update(endpoint)
            } else {
                UserServiceEndpointRegistry.shared.clear()
            }
            reply(nil)
        }

        func extensionRequirements(reply: @escaping (Bool, Bool, NSError?) -> Void) {
            Task {
                do {
                    try await service.waitForServiceReady()
                } catch {
                    reply(false, false, error as NSError)
                    return
                }
                guard let commandServer = service.commandServer else {
                    reply(false, false, NSError(domain: "CommandXPC", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Command server not available",
                    ]))
                    return
                }
                let needWIFI = commandServer.needWIFIState()
                let needProcess = commandServer.needFindProcess()
                reply(needWIFI, needProcess, nil)
            }
        }

        private func connectToUnixSocket(path: String) throws -> FileHandle {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw NSError(domain: "CommandXPC", code: Int(errno), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create socket: \(String(cString: strerror(errno)))",
                ])
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
            withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
                _ = path.withCString { cString in
                    strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), cString, pathSize - 1)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connectResult >= 0 else {
                close(fd)
                throw NSError(domain: "CommandXPC", code: Int(errno), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to connect to \(path): \(String(cString: strerror(errno)))",
                ])
            }

            return FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        }
    }

    public class CommandXPCDialer: NSObject, LibboxXPCDialerProtocol {
        public static let shared = CommandXPCDialer()

        public func dialXPC(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Int32 = -1
            var resultError: Error?

            let machServiceName = AppConfiguration.appGroupID + ".system"
            let connection = NSXPCConnection(machServiceName: machServiceName)
            let remoteInterface = NSXPCInterface(with: CommandXPCProtocol.self)
            CommandXPC.configureInterface(remoteInterface)
            connection.remoteObjectInterface = remoteInterface
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                logger.error("XPC proxy error: \(error.localizedDescription)")
                resultError = error
                semaphore.signal()
            } as! CommandXPCProtocol

            proxy.connectToCommandServer { handle, error in
                if let error {
                    logger.error("connectToCommandServer error: \(error.localizedDescription)")
                    resultError = error
                } else if let handle {
                    result = dup(handle.fileDescriptor)
                }
                semaphore.signal()
            }

            semaphore.wait()
            connection.invalidate()

            if let error = resultError {
                throw error
            }
            if result < 0 {
                logger.error("dialXPC failed: No file handle returned")
                throw NSError(domain: "CommandXPCDialer", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No file handle returned",
                ])
            }
            ret0_?.pointee = result
        }
    }

    public enum CommandXPC {
        public static func configureInterface(_ interface: NSXPCInterface) {
            let fileHandleClasses = NSSet(array: [FileHandle.self]) as! Set<AnyHashable>
            interface.setClasses(
                fileHandleClasses,
                for: #selector(CommandXPCProtocol.connectToCommandServer(reply:)),
                argumentIndex: 0,
                ofReply: true
            )
            let endpointClasses = NSSet(array: [NSXPCListenerEndpoint.self]) as! Set<AnyHashable>
            interface.setClasses(
                endpointClasses,
                for: #selector(CommandXPCProtocol.registerUserServiceEndpoint(_:reply:)),
                argumentIndex: 0,
                ofReply: false
            )
        }
    }
#endif
