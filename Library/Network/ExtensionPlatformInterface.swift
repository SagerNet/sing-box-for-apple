import Foundation
import Libbox
import NetworkExtension

public class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private let tunnel: NEPacketTunnelProvider
    private let commandServer: LibboxCommandServer
    private var networkSettings: NEPacketTunnelNetworkSettings?

    init(_ tunnel: NEPacketTunnelProvider, _ logServer: LibboxCommandServer) {
        self.tunnel = tunnel
        commandServer = logServer
    }

    public func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else {
            throw NSError(domain: "nil options", code: 0)
        }
        guard let ret0_ else {
            throw NSError(domain: "nil return pointer", code: 0)
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            var error: NSError?
            let dnsServer = options.getDNSServerAddress(&error)
            if let error {
                throw error
            }
            settings.dnsSettings = NEDNSSettings(servers: [dnsServer])

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            let ipv4AddressIterator = options.getInet4Address()!
            while ipv4AddressIterator.hasNext() {
                let ipv4Prefix = ipv4AddressIterator.next()!
                ipv4Address.append(ipv4Prefix.address)
                ipv4Mask.append(ipv4Prefix.mask())
            }
            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            let inet4RouteAddressIterator = options.getInet4RouteAddress()!
            if inet4RouteAddressIterator.hasNext() {
                while inet4RouteAddressIterator.hasNext() {
                    let ipv4RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv4Routes.append(NEIPv4Route(destinationAddress: ipv4RoutePrefix.address, subnetMask: ipv4RoutePrefix.mask()))
                }
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }
            for (index, address) in ipv4Address.enumerated() {
                ipv4Routes.append(NEIPv4Route(destinationAddress: address, subnetMask: ipv4Mask[index]))
            }
            ipv4Settings.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4Settings

            var ipv6Address: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            let ipv6AddressIterator = options.getInet6Address()!
            while ipv6AddressIterator.hasNext() {
                let ipv6Prefix = ipv6AddressIterator.next()!
                ipv6Address.append(ipv6Prefix.address)
                ipv6Prefixes.append(NSNumber(value: ipv6Prefix.prefix))
            }
            let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
            var ipv6Routes: [NEIPv6Route] = []
            let inet6RouteAddressIterator = options.getInet6RouteAddress()!
            if inet6RouteAddressIterator.hasNext() {
                while inet6RouteAddressIterator.hasNext() {
                    let ipv6RoutePrefix = inet4RouteAddressIterator.next()!
                    ipv6Routes.append(NEIPv6Route(destinationAddress: ipv6RoutePrefix.description, networkPrefixLength: NSNumber(value: ipv6RoutePrefix.prefix)))
                }
            } else {
                ipv6Routes.append(NEIPv6Route.default())
            }
            ipv6Settings.includedRoutes = ipv6Routes
            settings.ipv6Settings = ipv6Settings
        }

        if options.isHTTPProxyEnabled() {
            let proxySettings = NEProxySettings()
            let proxyServer = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
            proxySettings.httpEnabled = true
            proxySettings.httpServer = proxyServer
            proxySettings.httpsEnabled = true
            proxySettings.httpsServer = proxyServer
            settings.proxySettings = proxySettings
        }

        networkSettings = settings
        try runBlocking { [self] in
            try await tunnel.setTunnelNetworkSettings(settings)
        }

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }

        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "missing file descriptor", code: 0)
        }
    }

    public func usePlatformAutoDetectControl() -> Bool {
        true
    }

    public func autoDetectControl(_: Int32) throws {}

    public func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32, destinationAddress _: String?, destinationPort _: Int32, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func packageName(byUid _: Int32, error _: NSErrorPointer) -> String {
        ""
    }

    public func uid(byPackageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func useProcFS() -> Bool {
        false
    }

    public func writeLog(_ message: String?) {
        guard let message else {
            return
        }
        commandServer.writeMessage(message)
    }

    public func usePlatformDefaultInterfaceMonitor() -> Bool {
        false
    }

    public func startDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}

    public func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}

    public func useGetter() -> Bool {
        false
    }

    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "not implemented", code: 0)
    }

    public func underNetworkExtension() -> Bool {
        true
    }

    public func clearDNSCache() {
        guard let networkSettings else {
            return
        }
        tunnel.reasserting = true
        tunnel.setTunnelNetworkSettings(nil) { _ in
        }
        tunnel.setTunnelNetworkSettings(networkSettings) { _ in
        }
        tunnel.reasserting = false
    }
    
    public func closeTun() throws {
        tunnel.setTunnelNetworkSettings(nil) { _ in
        }
    }
}
