import Foundation
import Libbox
import NetworkExtension
import os.log
#if os(iOS)
    import WidgetKit
#endif
#if os(macOS)
    import CoreLocation
#endif

open class ExtensionProvider: NEPacketTunnelProvider {
    private static let logger = Logger(category: "ExtensionProvider")

    public private(set) var commandServer: LibboxCommandServer?
    private var platformInterface: ExtensionPlatformInterface!
    public var tunnelOptions: [String: NSObject]?
    private var startOptionsURL: URL?

    public struct OverridePreferences {
        public var includeAllNetworks: Bool = false
        public var systemProxyEnabled: Bool = true
        public var excludeDefaultRoute: Bool = false
        public var autoRouteUseSubRangesByDefault: Bool = false
        public var excludeAPNsRoute: Bool = false
    }

    public var overridePreferences: OverridePreferences?

    private func applyStartOptions(_ options: [String: NSObject]) {
        tunnelOptions = options
        var prefs = OverridePreferences()
        prefs.includeAllNetworks = (options["includeAllNetworks"] as? NSNumber)?.boolValue ?? false
        prefs.systemProxyEnabled = (options["systemProxyEnabled"] as? NSNumber)?.boolValue ?? true
        prefs.excludeDefaultRoute = (options["excludeDefaultRoute"] as? NSNumber)?.boolValue ?? false
        prefs.autoRouteUseSubRangesByDefault = (options["autoRouteUseSubRangesByDefault"] as? NSNumber)?.boolValue ?? false
        prefs.excludeAPNsRoute = (options["excludeAPNsRoute"] as? NSNumber)?.boolValue ?? false
        overridePreferences = prefs
    }

    private func persistStartOptions(_ options: [String: NSObject]) throws {
        guard let startOptionsURL else {
            return
        }
        let data = try ExtensionStartOptions.encode(options)
        try data.write(to: startOptionsURL, options: .atomic)
    }

    #if os(macOS)
        private var xpcListener: NSXPCListener?
        private var xpcService: CommandXPCService?
        private var locationManager: CLLocationManager?
        private var locationDelegate: stubLocationDelegate?
    #endif

    override open func startTunnel(options startOptions: [String: NSObject]?) async throws {
        let basePath: String
        let workingPath: String
        let tempPath: String

        #if os(macOS)
            if Variant.useSystemExtension {
                let containerURL = FileManager.default.homeDirectoryForCurrentUser
                basePath = containerURL.path
                workingPath = containerURL.appendingPathComponent("Working").path
                tempPath = containerURL.appendingPathComponent("Temp").path
            } else {
                basePath = FilePath.sharedDirectory.relativePath
                workingPath = FilePath.workingDirectory.relativePath
                tempPath = FilePath.cacheDirectory.relativePath
            }
        #else
            basePath = FilePath.sharedDirectory.relativePath
            workingPath = FilePath.workingDirectory.relativePath
            tempPath = FilePath.cacheDirectory.relativePath
        #endif

        startOptionsURL = URL(fileURLWithPath: basePath).appendingPathComponent(ExtensionStartOptions.snapshotFileName)
        var effectiveOptions = startOptions
        if let startOptions {
            do {
                try persistStartOptions(startOptions)
            } catch {
                throw ExtensionStartupError("(packet-tunnel) error: persist start options: \(error.localizedDescription)")
            }
        } else if let startOptionsURL, FileManager.default.fileExists(atPath: startOptionsURL.path) {
            do {
                let data = try Data(contentsOf: startOptionsURL)
                effectiveOptions = try ExtensionStartOptions.decode(data)
            } catch {
                throw ExtensionStartupError("(packet-tunnel) error: load start options: \(error.localizedDescription)")
            }
        } else {
            throw ExtensionStartupError("(packet-tunnel) error: missing start options")
        }

        if let effectiveOptions {
            applyStartOptions(effectiveOptions)
        }

        let options = LibboxSetupOptions()
        options.basePath = basePath
        options.workingPath = workingPath
        options.tempPath = tempPath

        options.logMaxLines = 3000

        #if os(tvOS)
            if let port = effectiveOptions?["commandServerPort"] as? NSNumber {
                options.commandServerListenPort = port.int32Value
            }
            if let secret = effectiveOptions?["commandServerSecret"] as? String {
                options.commandServerSecret = secret
            }
        #endif

        var setupError: NSError?
        LibboxSetup(options, &setupError)
        if let setupError {
            throw ExtensionStartupError("(packet-tunnel) error: setup service: \(setupError.localizedDescription)")
        }

        let ignoreMemoryLimit = (effectiveOptions?["ignoreMemoryLimit"] as? NSNumber)?.boolValue ?? false
        LibboxSetMemoryLimit(!ignoreMemoryLimit)

        if platformInterface == nil {
            platformInterface = ExtensionPlatformInterface(self)
        }
        var error: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &error)
        if let error {
            throw ExtensionStartupError("(packet-tunnel): create command server error: \(error.localizedDescription)")
        }
        do {
            try commandServer!.start()
        } catch {
            throw ExtensionStartupError("(packet-tunnel): start command server error: \(error.localizedDescription)")
        }

        #if os(macOS)
            if Variant.useSystemExtension {
                let socketPath = options.basePath + "/command.sock"
                xpcService = CommandXPCService(socketPath: socketPath)
                let machServiceName = AppConfiguration.appGroupID + ".system"
                xpcListener = NSXPCListener(machServiceName: machServiceName)
                xpcListener!.delegate = xpcService
                xpcListener!.resume()
                Self.logger.info("set Command Server")
                xpcService!.commandServer = commandServer
            }
        #endif

        writeMessage("(packet-tunnel): Here I stand")
        try await startService()
        #if os(macOS)
            if Variant.useSystemExtension {
                xpcService!.markServiceReady()
            }
        #endif
        #if os(iOS)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadControls(ofKind: ExtensionProfile.controlKind)
            }
        #endif
    }

    func writeMessage(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(2, message: message)
        }
    }

    private func startService() async throws {
        guard let configContent = tunnelOptions?["configContent"] as? String else {
            throw ExtensionStartupError("(packet-tunnel) error: missing configContent in tunnel options")
        }

        let options = LibboxOverrideOptions()
        do {
            try commandServer!.startOrReloadService(configContent, options: options)
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: start service: \(error.localizedDescription)")
        }
        #if os(macOS)
            if !Variant.useSystemExtension, commandServer!.needWIFIState() {
                locationManager = CLLocationManager()
                locationDelegate = stubLocationDelegate()
                locationManager?.delegate = locationDelegate
                locationManager?.requestLocation()
            }
        #endif
    }

    #if os(macOS)

        class stubLocationDelegate: NSObject, CLLocationManagerDelegate {
            func locationManagerDidChangeAuthorization(_: CLLocationManager) {}

            func locationManager(_: CLLocationManager, didUpdateLocations _: [CLLocation]) {}

            func locationManager(_: CLLocationManager, didFailWithError _: Error) {}
        }

    #endif

    func stopService() {
        do {
            try commandServer?.closeService()
        } catch {
            writeMessage("(packet-tunnel) stop service: \(error.localizedDescription)")
        }
        if let platformInterface {
            platformInterface.reset()
        }
    }

    func reloadService() async throws {
        writeMessage("(packet-tunnel) reloading service")
        reasserting = true
        defer {
            reasserting = false
        }
        try await startService()
    }

    override open func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
        #if os(macOS)
            if Variant.useSystemExtension {
                xpcListener?.invalidate()
                xpcListener = nil
                xpcService?.commandServer = nil
                xpcService = nil
                UserServiceEndpointRegistry.shared.clear()
            }
            locationManager = nil
            locationDelegate = nil
        #endif
        #if os(iOS)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadControls(ofKind: ExtensionProfile.controlKind)
            }
        #endif
    }

    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        do {
            let options = try ExtensionStartOptions.decode(messageData)
            applyStartOptions(options)
            try persistStartOptions(options)
            try await reloadService()
            return nil
        } catch {
            return error.localizedDescription.data(using: .utf8)
        }
    }

    override open func sleep() async {
        if let commandServer {
            commandServer.pause()
        }
    }

    override open func wake() {
        if let commandServer {
            commandServer.wake()
        }
    }
}
