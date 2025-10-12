import Foundation
import Libbox
import NetworkExtension
#if os(iOS)
    import WidgetKit
#endif
#if os(macOS)
    import CoreLocation
#endif

open class ExtensionProvider: NEPacketTunnelProvider {
    public var username: String?
    private var commandServer: LibboxCommandServer!
    private var platformInterface: ExtensionPlatformInterface!

    override open func startTunnel(options _: [String: NSObject]?) async throws {
        LibboxClearServiceError()

        let options = LibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath
        var setupError: NSError?
        LibboxSetup(options, &setupError)
        if let setupError {
            throw ExtensionStartupError("(packet-tunnel) error: setup service: \(setupError.localizedDescription)")
        }

        var stderrError: NSError?
        LibboxRedirectStderr(FilePath.cacheDirectory.appendingPathComponent("stderr.log").relativePath, &stderrError)
        if let stderrError {
            throw ExtensionStartupError("(packet-tunnel) redirect stderr error: \(stderrError.localizedDescription)")
        }

        await LibboxSetMemoryLimit(!SharedPreferences.ignoreMemoryLimit.get())

        if platformInterface == nil {
            platformInterface = ExtensionPlatformInterface(self)
        }
        var error: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &error)
        if let error {
            throw ExtensionStartupError("(packet-tunnel): create command server error: \(error.localizedDescription)")
        }
        do {
            try commandServer.start()
        } catch {
            throw ExtensionStartupError("(packet-tunnel): start command server error: \(error.localizedDescription)")
        }
        writeMessage("(packet-tunnel): Here I stand")
        try await startService()
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

    public func writeFatalError(_ message: String) {
        #if DEBUG
            NSLog(message)
        #endif
        if let commandServer {
            commandServer.setError(message)
        }
        cancelTunnelWithError(nil)
    }

    private func startService() async throws {
        let profile: Profile?
        do {
            profile = try await ProfileManager.get(Int64(SharedPreferences.selectedProfileID.get()))
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: read selected profile: \(error.localizedDescription)")
        }
        guard let profile else {
            throw ExtensionStartupError("(packet-tunnel) error: missing selected profile")
        }
        let configContent: String
        do {
            configContent = try profile.read()
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: read config file \(profile.path): \(error.localizedDescription)")
        }
        let options = LibboxOverrideOptions()
        do {
            try commandServer.startOrReloadService(configContent, options: options)
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: start service: \(error.localizedDescription)")
        }
        #if os(macOS)
            await SharedPreferences.startedByUser.set(true)
            if commandServer.needWIFIState() {
                if !Variant.useSystemExtension {
                    locationManager = CLLocationManager()
                    locationDelegate = stubLocationDelegate()
                    locationManager?.delegate = locationDelegate
                    locationManager?.requestLocation()
                } else {
                    writeMessage("(packet-tunnel) WIFI SSID and BSSID information is not currently available in the standalone version of SFM. We are working on resolving this issue.")
                }
            }
        #endif
    }

    #if os(macOS)

        private var locationManager: CLLocationManager?
        private var locationDelegate: stubLocationDelegate?

        class stubLocationDelegate: NSObject, CLLocationManagerDelegate {
            func locationManagerDidChangeAuthorization(_: CLLocationManager) {}

            func locationManager(_: CLLocationManager, didUpdateLocations _: [CLLocation]) {}

            func locationManager(_: CLLocationManager, didFailWithError _: Error) {}
        }

    #endif

    func stopService() {
        do {
            try commandServer.closeService()
        } catch {
            writeMessage("(packet-tunnel) error: stop service: \(error.localizedDescription)")
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
            if reason == .userInitiated {
                await SharedPreferences.startedByUser.set(reason == .userInitiated)
            }
        #endif
        #if os(iOS)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadControls(ofKind: ExtensionProfile.controlKind)
            }
        #endif
    }

    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        messageData
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
