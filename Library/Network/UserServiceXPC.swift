#if os(macOS)
    import Foundation
    import Libbox
    import os

    private let logger = Logger(category: "UserServiceXPC")

    @objc public protocol UserServiceProtocol {
        func getWIFIState(reply: @escaping (String?, String?, NSError?) -> Void)
        func connectSSHAgent(reply: @escaping (FileHandle?, NSError?) -> Void)
        func sendNotification(
            identifier: String,
            typeName: String,
            typeID: Int32,
            title: String,
            subtitle: String,
            body: String,
            openURL: String,
            reply: @escaping (NSError?) -> Void
        )
        func cancelNotification(
            identifier: String,
            reply: @escaping (NSError?) -> Void
        )
    }

    public enum UserServiceXPC {
        public static func configureInterface(_ interface: NSXPCInterface) {
            let fileHandleClasses = NSSet(array: [FileHandle.self]) as! Set<AnyHashable>
            interface.setClasses(
                fileHandleClasses,
                for: #selector(UserServiceProtocol.connectSSHAgent(reply:)),
                argumentIndex: 0,
                ofReply: true
            )
        }
    }

    public class UserServiceClient {
        public static let shared = UserServiceClient()

        private var connection: NSXPCConnection?
        private let connectionLock = NSLock()

        private init() {}

        func updateEndpoint(_ endpoint: NSXPCListenerEndpoint?) {
            var newConnection: NSXPCConnection?
            if let endpoint {
                let endpointConnection = NSXPCConnection(listenerEndpoint: endpoint)
                let remoteInterface = NSXPCInterface(with: UserServiceProtocol.self)
                UserServiceXPC.configureInterface(remoteInterface)
                endpointConnection.remoteObjectInterface = remoteInterface
                endpointConnection.invalidationHandler = { [weak self, weak endpointConnection] in
                    guard let self else { return }
                    connectionLock.lock()
                    if connection === endpointConnection {
                        connection = nil
                    }
                    connectionLock.unlock()
                }
                endpointConnection.resume()
                newConnection = endpointConnection
            }
            connectionLock.lock()
            let oldConnection = connection
            connection = newConnection
            connectionLock.unlock()
            oldConnection?.invalidate()
        }

        private func call(
            _ operation: String,
            _ body: (UserServiceProtocol, @escaping (NSError?) -> Void) -> Void
        ) throws {
            connectionLock.lock()
            let currentConnection = connection
            connectionLock.unlock()
            guard let currentConnection else {
                logger.error("\(operation): no UserService connection")
                throw NSError(domain: "UserService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "UserService connection unavailable",
                ])
            }

            let semaphore = DispatchSemaphore(value: 0)
            var resultError: NSError?
            let proxy = currentConnection.remoteObjectProxyWithErrorHandler { error in
                resultError = error as NSError
                semaphore.signal()
            } as! UserServiceProtocol
            body(proxy) { error in
                resultError = error
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + .seconds(5)) == .timedOut {
                logger.error("\(operation): timeout")
                throw NSError(domain: "UserService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) request timeout",
                ])
            }
            if let resultError {
                logger.error("\(operation) error: \(resultError.localizedDescription)")
                throw resultError
            }
        }

        public func readWIFIState() -> LibboxWIFIState? {
            var state: LibboxWIFIState?
            do {
                try call("readWIFIState") { proxy, reply in
                    proxy.getWIFIState { ssid, bssid, error in
                        if let ssid, let bssid {
                            state = LibboxWIFIState(ssid, wifiBSSID: bssid)
                        }
                        reply(error)
                    }
                }
            } catch {
                return nil
            }
            return state
        }

        public func connectSSHAgent() -> Int32? {
            var fd: Int32?
            do {
                try call("connectSSHAgent") { proxy, reply in
                    proxy.connectSSHAgent { handle, error in
                        if error == nil, let handle {
                            fd = dup(handle.fileDescriptor)
                        }
                        reply(error)
                    }
                }
            } catch {
                return nil
            }
            return fd
        }

        public func sendNotification(_ notification: LibboxNotification) throws {
            try call("sendNotification") { proxy, reply in
                proxy.sendNotification(
                    identifier: notification.identifier,
                    typeName: notification.typeName,
                    typeID: notification.typeID,
                    title: notification.title,
                    subtitle: notification.subtitle,
                    body: notification.body,
                    openURL: notification.openURL,
                    reply: reply
                )
            }
        }

        public func cancelNotification(_ identifier: String) throws {
            try call("cancelNotification") { proxy, reply in
                proxy.cancelNotification(identifier: identifier, reply: reply)
            }
        }
    }
#endif
