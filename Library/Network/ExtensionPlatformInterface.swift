import Foundation
import Libbox
import NetworkExtension
import os
import UserNotifications
#if os(macOS)
    import CoreWLAN
#endif

public class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private static let logger = Logger(category: "ExtensionPlatformInterface")
    private let tunnel: ExtensionProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?

    init(_ tunnel: ExtensionProvider) {
        self.tunnel = tunnel
    }

    public func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTun0(options, ret0_)
        }
    }

    private func openTun0(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nil options")])
        }
        guard let ret0_ else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nil return pointer")])
        }

        let prefs = tunnel.overridePreferences ?? ExtensionProvider.OverridePreferences()
        let autoRouteUseSubRangesByDefault = prefs.autoRouteUseSubRangesByDefault
        let excludeAPNs = prefs.excludeAPNsRoute
        let excludeDefaultRoute = prefs.excludeDefaultRoute
        let systemProxyEnabled = prefs.systemProxyEnabled

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            var dnsSettings: NEDNSSettings?
            if options.getDNSMode()!.value != LibboxDNSModeDisabled {
                let dnsServerIterator = try options.getDNSServerAddress()
                var dnsServers: [String] = []
                while dnsServerIterator.hasNext() {
                    dnsServers.append(dnsServerIterator.next())
                }
                if !dnsServers.isEmpty {
                    let newDNSSettings = NEDNSSettings(servers: dnsServers)
                    settings.dnsSettings = newDNSSettings
                    dnsSettings = newDNSSettings
                }
            }

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            let ipv4AddressIterator = options.getInet4Address()!
            while ipv4AddressIterator.hasNext() {
                let ipv4Prefix = ipv4AddressIterator.next()!
                ipv4Address.append(ipv4Prefix.address())
                ipv4Mask.append(ipv4Prefix.mask())
            }

            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            var ipv4ExcludeRoutes: [NEIPv4Route] = []

            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
                }
            } else if autoRouteUseSubRangesByDefault {
                ipv4Routes.append(NEIPv4Route(destinationAddress: "1.0.0.0", subnetMask: "255.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "2.0.0.0", subnetMask: "254.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "4.0.0.0", subnetMask: "252.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "8.0.0.0", subnetMask: "248.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "16.0.0.0", subnetMask: "240.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "32.0.0.0", subnetMask: "224.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "64.0.0.0", subnetMask: "192.0.0.0"))
                ipv4Routes.append(NEIPv4Route(destinationAddress: "128.0.0.0", subnetMask: "128.0.0.0"))
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }

            let inet4RouteExcludeAddressIterator = options.getInet4RouteExcludeAddress()!
            while inet4RouteExcludeAddressIterator.hasNext() {
                let ipv4RoutePrefix = inet4RouteExcludeAddressIterator.next()!
                ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address(), subnetMask: ipv4RoutePrefix.mask()))
            }
            if excludeDefaultRoute, !ipv4Routes.isEmpty {
                if !ipv4ExcludeRoutes.contains(where: { it in
                    it.destinationAddress == "0.0.0.0" && it.destinationSubnetMask == "255.255.255.254"
                }) {
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.255.255.254"))
                }
            }
            if excludeAPNs, !ipv4Routes.isEmpty {
                if !ipv4ExcludeRoutes.contains(where: { it in
                    it.destinationAddress == "17.0.0.0" && it.destinationSubnetMask == "255.0.0.0"
                }) {
                    ipv4ExcludeRoutes.append(NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"))
                }
            }

            ipv4Settings.includedRoutes = ipv4Routes
            ipv4Settings.excludedRoutes = ipv4ExcludeRoutes
            settings.ipv4Settings = ipv4Settings

            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            let ipv6AddressIterator = options.getInet6Address()!
            while ipv6AddressIterator.hasNext() {
                let ipv6Prefix = ipv6AddressIterator.next()!
                ipv6Address.append(ipv6Prefix.address())
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix()))
            }
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            var ipv6ExcludeRoutes: [NEIPv6Route] = []

            let inet6RouteAddressIterator = options.getInet6RouteAddress()!
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    let ipv6RoutePrefix = inet6RouteAddressIterator.next()!
                    ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
                }
            } else if autoRouteUseSubRangesByDefault {
                ipv6Routes.append(NEIPv6Route(destinationAddress: "100::", networkPrefixLength: 8))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "200::", networkPrefixLength: 7))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "400::", networkPrefixLength: 6))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "800::", networkPrefixLength: 5))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "1000::", networkPrefixLength: 4))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "2000::", networkPrefixLength: 3))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "4000::", networkPrefixLength: 2))
                ipv6Routes.append(NEIPv6Route(destinationAddress: "8000::", networkPrefixLength: 1))
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }

            let inet6RouteExcludeAddressIterator = options.getInet6RouteExcludeAddress()!
            while inet6RouteExcludeAddressIterator.hasNext() {
                let ipv6RoutePrefix = inet6RouteExcludeAddressIterator.next()!
                ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.address(), networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix())))
            }

            if excludeDefaultRoute, !ipv6Routes.isEmpty {
                if !ipv6ExcludeRoutes.contains(where: { it in
                    it.destinationAddress == "::" && it.destinationNetworkPrefixLength == 127
                }) {
                    ipv6ExcludeRoutes.append(NEIPv6Route(destinationAddress: "::", networkPrefixLength: 127))
                }
            }

            ipv6Settings.includedRoutes = ipv6Routes
            ipv6Settings.excludedRoutes = ipv6ExcludeRoutes
            settings.ipv6Settings = ipv6Settings

            let hasDefaultRoute = ipv4Routes.contains(where: {
                $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0"
            })
            if !hasDefaultRoute {
                dnsSettings?.matchDomains = [""]
                dnsSettings?.matchDomainsNoSearch = true
            }
        }

        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpServer = proxyServer
            proxySettings.httpsServer = proxyServer
            if systemProxyEnabled {
                proxySettings.httpEnabled = true
                proxySettings.httpsEnabled = true
            }
            var bypassDomains: [String] = []
            let bypassDomainIterator = options.getHTTPProxyBypassDomain()!
            while bypassDomainIterator.hasNext() {
                bypassDomains.append(bypassDomainIterator.next())
            }
            if excludeAPNs {
                if !bypassDomains.contains(where: { it in
                    it == "push.apple.com"
                }) {
                    bypassDomains.append("push.apple.com")
                }
            }
            if !bypassDomains.isEmpty {
                proxySettings.exceptionList = bypassDomains
            }
            var matchDomains: [String] = []
            let matchDomainIterator = options.getHTTPProxyMatchDomain()!
            while matchDomainIterator.hasNext() {
                matchDomains.append(matchDomainIterator.next())
            }
            if !matchDomains.isEmpty {
                proxySettings.matchDomains = matchDomains
            }
            settings.proxySettings = proxySettings
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }

        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing file descriptor")])
        }
    }

    public func usePlatformAutoDetectControl() -> Bool {
        false
    }

    public func autoDetectControl(_: Int32) throws {}

    public func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32, destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        #if os(macOS)
            if Variant.useSystemExtension {
                guard let sourceAddress, let destinationAddress else {
                    throw NSError(domain: "findConnectionOwner", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Missing source or destination address",
                    ])
                }
                let owner = try RootHelperClient.shared.findConnectionOwner(
                    ipProtocol: ipProtocol,
                    sourceAddress: sourceAddress,
                    sourcePort: sourcePort,
                    destinationAddress: destinationAddress,
                    destinationPort: destinationPort
                )
                let result = LibboxConnectionOwner()
                result.userId = owner.userId
                result.userName = owner.userName
                result.processPath = owner.processPath
                return result
            }
        #endif
        throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Not implemented")])
    }

    public func useProcFS() -> Bool {
        false
    }

    public func writeLog(_ message: String?) {
        guard let message else {
            return
        }
        tunnel.writeMessage(message)
    }

    private var nwMonitor: NWPathMonitor?

    public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else {
            return
        }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            self.onUpdateDefaultInterface(listener, path)
            semaphore.signal()
            monitor.pathUpdateHandler = { path in
                self.onUpdateDefaultInterface(listener, path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func onUpdateDefaultInterface(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        guard path.status != .unsatisfied,
              let defaultInterface = path.availableInterfaces.first
        else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(defaultInterface.name, interfaceIndex: Int32(defaultInterface.index), isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }

    public func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "NWMonitor not started")])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return networkInterfaceArray([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let interface = LibboxNetworkInterface()
            interface.name = it.name
            interface.index = Int32(it.index)
            switch it.type {
            case .wifi:
                interface.type = LibboxInterfaceTypeWIFI
            case .cellular:
                interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                interface.type = LibboxInterfaceTypeEthernet
            default:
                interface.type = LibboxInterfaceTypeOther
            }
            interfaces.append(interface)
        }
        return networkInterfaceArray(interfaces)
    }

    class networkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        init(_ array: [LibboxNetworkInterface]) {
            iterator = array.makeIterator()
        }

        private var nextValue: LibboxNetworkInterface?

        func hasNext() -> Bool {
            nextValue = iterator.next()
            return nextValue != nil
        }

        func next() -> LibboxNetworkInterface? {
            nextValue
        }
    }

    public func underNetworkExtension() -> Bool {
        true
    }

    public func includeAllNetworks() -> Bool {
        #if os(tvOS)
            return false
        #else
            return tunnel.overridePreferences?.includeAllNetworks ?? false
        #endif
    }

    public func clearDNSCache() {
        guard let networkSettings else {
            return
        }
        runBlocking {
            self.tunnel.reasserting = true
            defer { self.tunnel.reasserting = false }
            await withCheckedContinuation { continuation in
                self.tunnel.setTunnelNetworkSettings(nil) { _ in
                    continuation.resume()
                }
            }
            await withCheckedContinuation { continuation in
                self.tunnel.setTunnelNetworkSettings(networkSettings) { _ in
                    continuation.resume()
                }
            }
        }
    }

    public func readWIFIState() -> LibboxWIFIState? {
        #if os(iOS)
            let network = runBlocking {
                await NEHotspotNetwork.fetchCurrent()
            }
            guard let network else {
                return nil
            }
            return LibboxWIFIState(network.ssid, wifiBSSID: network.bssid)!
        #elseif os(macOS)
            if Variant.useSystemExtension {
                return UserServiceClient.shared.readWIFIState()
            }
            guard let interface = CWWiFiClient.shared().interface() else {
                return nil
            }
            guard let ssid = interface.ssid() else {
                return nil
            }
            guard let bssid = interface.bssid() else {
                return nil
            }
            return LibboxWIFIState(ssid, wifiBSSID: bssid)!
        #else
            return nil
        #endif
    }

    public func readWIFISSID() -> String? {
        #if os(iOS)
            return runBlocking {
                await NEHotspotNetwork.fetchCurrent()?.ssid
            }
        #elseif os(macOS)
            return CWWiFiClient.shared().interface()?.ssid()
        #else
            return nil
        #endif
    }

    public func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        #if os(macOS)
            if Variant.useSystemExtension {
                guard let fd = UserServiceClient.shared.connectSSHAgent() else {
                    throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to connect to SSH agent",
                    ])
                }
                ret0_?.pointee = fd
                return
            }
        #endif
        throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "SSH agent forwarding is not supported",
        ])
    }

    public func serviceStop() throws {
        tunnel.stopService()
    }

    public func serviceReload() throws {
        try runBlocking { [self] in
            try await tunnel.reloadService()
        }
    }

    public func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        let status = LibboxSystemProxyStatus()
        guard let networkSettings else {
            return status
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return status
        }
        if proxySettings.httpServer == nil {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    public func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard let networkSettings else {
            return
        }
        guard let proxySettings = networkSettings.proxySettings else {
            return
        }
        if proxySettings.httpServer == nil {
            return
        }
        if proxySettings.httpEnabled == isEnabled {
            return
        }
        proxySettings.httpEnabled = isEnabled
        proxySettings.httpsEnabled = isEnabled
        networkSettings.proxySettings = proxySettings
        try runBlocking {
            try await self.tunnel.setTunnelNetworkSettings(networkSettings)
        }
    }

    public func triggerNativeCrash() throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            fatalError("debug native crash")
        }
    }

    public func writeDebugMessage(_ message: String?) {
        guard let message else {
            return
        }
        Self.logger.debug("\(message, privacy: .public)")
    }

    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
        #if os(macOS)
            neighborCallbackListener?.invalidate()
            neighborCallbackListener = nil
            neighborCallbackHandler = nil
        #endif
    }

    public func send(_ notification: LibboxNotification?) throws {
        #if !os(tvOS)
            guard let notification else {
                return
            }
            #if os(macOS)
                if Variant.useSystemExtension {
                    try UserServiceClient.shared.sendNotification(notification)
                    return
                }
            #endif
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()

            content.title = notification.title
            content.subtitle = notification.subtitle
            content.body = notification.body
            if !notification.openURL.isEmpty {
                content.userInfo["OPEN_URL"] = notification.openURL
                content.categoryIdentifier = "OPEN_URL"
            }
            content.interruptionLevel = .active
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            try runBlocking {
                try await center.requestAuthorization(options: [.alert])
                try await center.add(request)
            }
        #endif
    }

    #if os(macOS)
        private var neighborCallbackListener: NSXPCListener?
        private var neighborCallbackHandler: NeighborCallbackHandler?
    #endif

    public func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {
        #if os(macOS)
            guard let listener else { return }
            if Variant.useSystemExtension {
                let handler = NeighborCallbackHandler(listener)
                let xpcListener = NSXPCListener.anonymous()
                xpcListener.delegate = handler
                xpcListener.resume()
                try RootHelperClient.shared.startNeighborMonitor(
                    callbackEndpoint: xpcListener.endpoint
                )
                neighborCallbackListener = xpcListener
                neighborCallbackHandler = handler
                return
            }
        #endif
    }

    public func registerMyInterface(_ name: String?) {
        #if os(macOS)
            guard let name, !name.isEmpty else { return }
            if Variant.useSystemExtension {
                try? RootHelperClient.shared.registerMyInterface(name: name)
            }
        #endif
    }

    public func closeNeighborMonitor(_: LibboxNeighborUpdateListenerProtocol?) throws {
        #if os(macOS)
            if Variant.useSystemExtension {
                try? RootHelperClient.shared.closeNeighborMonitor()
                neighborCallbackListener?.invalidate()
                neighborCallbackListener = nil
                neighborCallbackHandler = nil
                return
            }
        #endif
    }

    public func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? {
        nil
    }

    public func systemCertificates() -> (any LibboxStringIteratorProtocol)? {
        nil
    }

    public func usePlatformShell() -> Bool {
        #if os(macOS)
            return Variant.useSystemExtension
        #else
            return false
        #endif
    }

    public func checkPlatformShell() throws {
        #if os(macOS)
            _ = try RootHelperClient.shared.getVersion()
        #else
            throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "SSH server is not supported",
            ])
        #endif
    }

    public func openShellSession(_ user: LibboxPlatformUser?, command: String?, environ: (any LibboxStringIteratorProtocol)?, term: String?, rows: Int32, cols: Int32) throws -> any LibboxShellSessionProtocol {
        #if os(macOS)
            guard let user else {
                throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "missing user",
                ])
            }
            let command = command ?? ""
            let term = term ?? ""
            let envStrings = environ?.toArray() ?? []

            let groups = user.groups()?.toArray() ?? []
            let payload = PlatformUserPayload(
                username: user.username,
                uid: user.uid,
                gid: user.gid,
                homeDir: user.homeDir,
                shell: user.shell,
                groups: groups
            )

            let (fileHandle, handle) = try RootHelperClient.shared.openShellSession(
                user: payload,
                command: command,
                environ: envStrings,
                term: term,
                rows: rows,
                cols: cols
            )

            return RootHelperShellSession(fileHandle: fileHandle, handle: handle)
        #else
            throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "SSH server is not supported",
            ])
        #endif
    }

    public func readSystemSSHHostKey() throws -> LibboxStringBox {
        #if os(macOS)
            let keyData = try RootHelperClient.shared.readSystemSSHHostKey()
            let result = LibboxStringBox()
            result.value = keyData
            return result
        #else
            throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "not supported on this platform",
            ])
        #endif
    }

    public func lookupSFTPServer() throws -> LibboxStringBox {
        throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "lookupSFTPServer is not supported on Apple platforms",
        ])
    }

    public func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
        #if os(macOS)
            guard let username else {
                throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "lookupUser: username is required",
                ])
            }
            guard let pw = getpwnam(username) else {
                throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "user not found: \(username)",
                ])
            }
            let result = LibboxPlatformUser()
            result.username = String(cString: pw.pointee.pw_name)
            result.uid = Int32(pw.pointee.pw_uid)
            result.gid = Int32(pw.pointee.pw_gid)
            result.homeDir = String(cString: pw.pointee.pw_dir)
            if let shellPtr = pw.pointee.pw_shell {
                result.shell = String(cString: shellPtr)
            }

            var ngroups: Int32 = 64
            var groupIDs = [Int32](repeating: 0, count: Int(ngroups))
            var rc = groupIDs.withUnsafeMutableBufferPointer { buffer in
                getgrouplist(username, Int32(bitPattern: pw.pointee.pw_gid), buffer.baseAddress, &ngroups)
            }
            if rc == -1 {
                groupIDs = [Int32](repeating: 0, count: Int(ngroups))
                rc = groupIDs.withUnsafeMutableBufferPointer { buffer in
                    getgrouplist(username, Int32(bitPattern: pw.pointee.pw_gid), buffer.baseAddress, &ngroups)
                }
            }
            if rc == -1 {
                throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "getgrouplist failed for \(username)",
                ])
            }
            result.setGroups(Array(groupIDs.prefix(Int(ngroups))).toInt32Iterator())
            return result
        #else
            throw NSError(domain: "ExtensionPlatformInterface", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "SSH server is not supported",
            ])
        #endif
    }
}

#if os(macOS)
    private class NeighborCallbackHandler: NSObject, NSXPCListenerDelegate, NeighborTableListenerProtocol {
        private let listener: LibboxNeighborUpdateListenerProtocol

        init(_ listener: LibboxNeighborUpdateListenerProtocol) {
            self.listener = listener
        }

        func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
            let exportedInterface = NSXPCInterface(with: NeighborTableListenerProtocol.self)
            RootHelperXPC.configureListenerInterface(exportedInterface)
            newConnection.exportedInterface = exportedInterface
            newConnection.exportedObject = self
            newConnection.resume()
            return true
        }

        func updateNeighborTable(entries: NSArray) {
            let iterator = NeighborEntryArrayIterator(entries)
            listener.updateNeighborTable(iterator)
        }
    }

    private class NeighborEntryArrayIterator: NSObject, LibboxNeighborEntryIteratorProtocol {
        private var entries: [NeighborEntryResult]
        private var index = 0

        init(_ array: NSArray) {
            entries = array.compactMap { $0 as? NeighborEntryResult }
        }

        func hasNext() -> Bool {
            index < entries.count
        }

        func next() -> LibboxNeighborEntry? {
            guard index < entries.count else { return nil }
            let result = entries[index]
            index += 1
            let entry = LibboxNeighborEntry()
            entry.address = result.address
            entry.macAddress = result.macAddress
            entry.hostname = result.hostname
            return entry
        }
    }

    private class RootHelperShellSession: NSObject, LibboxShellSessionProtocol {
        private let fileHandle: FileHandle
        private let handle: String

        init(fileHandle: FileHandle, handle: String) {
            self.fileHandle = fileHandle
            self.handle = handle
        }

        func masterFD() -> Int32 {
            fileHandle.fileDescriptor
        }

        func resize(_ rows: Int32, cols: Int32) throws {
            var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
            let result = withUnsafeMutablePointer(to: &ws) { ptr in
                ioctl(fileHandle.fileDescriptor, TIOCSWINSZ, ptr)
            }
            if result < 0 {
                throw NSError(domain: "RootHelperShellSession", code: Int(Darwin.errno), userInfo: [
                    NSLocalizedDescriptionKey: "ioctl TIOCSWINSZ: \(String(cString: strerror(Darwin.errno)))",
                ])
            }
        }

        func signal(_ signal: Int32) throws {
            try RootHelperClient.shared.signalShellSession(handle: handle, signal: signal)
        }

        func waitExit(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
            let exitStatus = try RootHelperClient.shared.waitShellSession(handle: handle)
            ret0_?.pointee = exitStatus
        }

        func close() throws {
            try? RootHelperClient.shared.closeShellSession(handle: handle)
            fileHandle.closeFile()
        }
    }
#endif
