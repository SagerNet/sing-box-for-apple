#if os(macOS)
    import Foundation
    import Libbox
    import os

    private let logger = Logger(category: "UserServiceXPC")

    @objc public protocol UserServiceProtocol {
        func getWIFIState(reply: @escaping (String?, String?, NSError?) -> Void)
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
    }

    public class UserServiceClient {
        public static let shared = UserServiceClient()

        private var connection: NSXPCConnection?
        private let connectionLock = NSLock()

        private init() {}

        private func getConnection() -> NSXPCConnection? {
            connectionLock.lock()
            defer { connectionLock.unlock() }

            if let existing = connection {
                return existing
            }

            guard let endpoint = UserServiceEndpointRegistry.shared.get() else {
                logger.error("UserService endpoint unavailable")
                return nil
            }

            let newConnection = NSXPCConnection(listenerEndpoint: endpoint)
            newConnection.remoteObjectInterface = NSXPCInterface(with: UserServiceProtocol.self)

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

        private func getProxy() -> UserServiceProtocol? {
            guard let conn = getConnection() else {
                return nil
            }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
                guard let self else { return }
                logger.error("UserService XPC error: \(error.localizedDescription)")
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
            } as? UserServiceProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                return nil
            }
            return proxy
        }

        private func performXPCCallVoid(
            _ operation: String,
            call: (UserServiceProtocol, @escaping (NSError?) -> Void) -> Void
        ) throws {
            let semaphore = DispatchSemaphore(value: 0)
            var resultError: NSError?

            guard let proxy = getProxy() else {
                throw NSError(domain: "UserService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "UserService connection unavailable",
                ])
            }

            call(proxy) { error in
                resultError = error
                semaphore.signal()
            }

            let deadline = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: deadline) == .timedOut {
                let error = NSError(domain: "UserService", code: -1, userInfo: [
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

        public func readWIFIState() -> LibboxWIFIState? {
            let semaphore = DispatchSemaphore(value: 0)
            var resultSSID: String?
            var resultBSSID: String?

            guard let proxy = getProxy() else {
                logger.error("readWIFIState: no UserService connection")
                return nil
            }

            proxy.getWIFIState { ssid, bssid, error in
                if let error {
                    logger.error("readWIFIState error: \(error.localizedDescription)")
                } else {
                    resultSSID = ssid
                    resultBSSID = bssid
                }
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                logger.error("readWIFIState: timeout")
                return nil
            }

            guard let ssid = resultSSID, let bssid = resultBSSID else {
                return nil
            }

            return LibboxWIFIState(ssid, wifiBSSID: bssid)
        }

        public func sendNotification(_ notification: LibboxNotification) throws {
            try performXPCCallVoid("sendNotification") { proxy, reply in
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
    }
#endif
