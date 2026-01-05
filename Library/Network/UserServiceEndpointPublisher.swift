#if os(macOS)
    import CoreWLAN
    import Dispatch
    import Foundation
    import os
    import UserNotifications

    private let logger = Logger(category: "UserService")

    public extension Notification.Name {
        static let extensionRequiresWIFIState = Notification.Name("extensionRequiresWIFIState")
        static let extensionRequiresHelperService = Notification.Name("extensionRequiresHelperService")
        static let navigateToSettingsPage = Notification.Name("navigateToSettingsPage")
    }

    public final class UserServiceEndpointPublisher: NSObject, NSXPCListenerDelegate {
        public static let shared = UserServiceEndpointPublisher()

        private var listener: NSXPCListener?
        private let exportedObject = UserServiceHandler()

        public func start() {
            guard listener == nil else {
                return
            }
            let listener = NSXPCListener.anonymous()
            listener.delegate = self
            listener.resume()
            self.listener = listener
            registerEndpoint(listener.endpoint)
        }

        public func stop() {
            if let listener {
                listener.invalidate()
                self.listener = nil
            }
            registerEndpoint(nil)
        }

        public func refreshEndpointRegistration() {
            guard let listener else {
                return
            }
            registerEndpoint(listener.endpoint)
        }

        public func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            let bundleID = AppConfiguration.systemExtensionBundleID
            let requirement = "identifier \"\(bundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(AppConfiguration.teamID)\""
            do {
                try newConnection.setCodeSigningRequirement(requirement)
            } catch {
                logger.warning("Rejected XPC connection: \(error.localizedDescription)")
                return false
            }

            newConnection.exportedInterface = NSXPCInterface(with: UserServiceProtocol.self)
            newConnection.exportedObject = exportedObject
            newConnection.resume()
            return true
        }

        public func checkExtensionRequirements() {
            Task.detached {
                let machServiceName = AppConfiguration.appGroupID + ".system"
                let connection = NSXPCConnection(machServiceName: machServiceName)
                let remoteInterface = NSXPCInterface(with: CommandXPCProtocol.self)
                CommandXPC.configureInterface(remoteInterface)
                connection.remoteObjectInterface = remoteInterface
                connection.resume()

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    logger.error("Extension requirements check error: \(error.localizedDescription)")
                    connection.invalidate()
                }) as? CommandXPCProtocol else {
                    connection.invalidate()
                    return
                }

                proxy.extensionRequirements { needWIFI, needProcess, error in
                    if let error {
                        logger.error("Extension requirements error: \(error.localizedDescription)")
                        connection.invalidate()
                        return
                    }
                    if needWIFI {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .extensionRequiresWIFIState, object: nil)
                        }
                    }
                    if needProcess {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .extensionRequiresHelperService, object: nil)
                        }
                    }
                    connection.invalidate()
                }
            }
        }

        private func registerEndpoint(_ endpoint: NSXPCListenerEndpoint?) {
            let machServiceName = AppConfiguration.appGroupID + ".system"
            let connection = NSXPCConnection(machServiceName: machServiceName)
            let remoteInterface = NSXPCInterface(with: CommandXPCProtocol.self)
            CommandXPC.configureInterface(remoteInterface)
            connection.remoteObjectInterface = remoteInterface
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                logger.error("UserService registration error: \(error.localizedDescription)")
                connection.invalidate()
            }) as? CommandXPCProtocol else {
                connection.invalidate()
                return
            }

            proxy.registerUserServiceEndpoint(endpoint) { error in
                if let error {
                    logger.error("UserService register failed: \(error.localizedDescription)")
                }
                connection.invalidate()
            }
        }
    }

    private final class UserServiceHandler: NSObject, UserServiceProtocol {
        func getWIFIState(reply: @escaping (String?, String?, NSError?) -> Void) {
            let client = CWWiFiClient.shared()
            guard let interface = client.interface() else {
                reply(nil, nil, nil)
                return
            }
            let ssid = interface.ssid()
            let bssid = interface.bssid()
            reply(ssid, bssid, nil)
        }

        func sendNotification(
            identifier: String,
            typeName _: String,
            typeID _: Int32,
            title: String,
            subtitle: String,
            body: String,
            openURL: String,
            reply: @escaping (NSError?) -> Void
        ) {
            Task {
                do {
                    let center = UNUserNotificationCenter.current()

                    let settings = await center.notificationSettings()

                    if settings.authorizationStatus == .notDetermined {
                        let granted = try await center.requestAuthorization(options: [.alert, .sound])
                        if !granted {
                            let error = NSError(domain: "UserService", code: -1, userInfo: [
                                NSLocalizedDescriptionKey: "Notification permission denied",
                            ])
                            logger.error("sendNotification error: \(error.localizedDescription)")
                            reply(error)
                            return
                        }
                    } else if settings.authorizationStatus == .denied {
                        let error = NSError(domain: "UserService", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: "Notification permission denied",
                        ])
                        logger.error("sendNotification error: \(error.localizedDescription)")
                        reply(error)
                        return
                    }

                    let content = UNMutableNotificationContent()
                    content.title = title
                    if !subtitle.isEmpty {
                        content.subtitle = subtitle
                    }
                    content.body = body
                    content.sound = .default

                    if !openURL.isEmpty {
                        content.userInfo["openURL"] = openURL
                    }

                    let request = UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: nil
                    )

                    try await center.add(request)
                    reply(nil)
                } catch {
                    let nsError = error as NSError
                    logger.error("sendNotification error: \(nsError.localizedDescription)")
                    reply(nsError)
                }
            }
        }
    }
#endif
