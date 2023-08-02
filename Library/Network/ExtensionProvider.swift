import Foundation
import Libbox
import NetworkExtension

open class ExtensionProvider: NEPacketTunnelProvider {
    public static let errorFile = FilePath.workingDirectory.appendingPathComponent("network_extension_error")

    public var username: String? = nil
    private var commandServer: LibboxCommandServer!
    private var boxService: LibboxBoxService!

    override open func startTunnel(options _: [String: NSObject]?) async throws {
        NSLog("Here I am")

        try? FileManager.default.removeItem(at: ExtensionProvider.errorFile)

        do {
            try FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        } catch {
            writeFatalError("(packet-tunnel) error: create working directory: \(error.localizedDescription)")
            return
        }

        if let username {
            var error: NSError?
            LibboxSetupWithUsername(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, username, &error)
            if let error {
                writeFatalError("(packet-tunnel) error: setup service: \(error.localizedDescription)")
                return
            }
        } else {
            var isTVOS = false
            #if os(tvOS)
                isTVOS = true
            #endif
            LibboxSetup(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, isTVOS)
        }

        var error: NSError?
        LibboxRedirectStderr(FilePath.cacheDirectory.appendingPathComponent("stderr.log").relativePath, &error)
        if let error {
            writeError("(packet-tunnel) redirect stderr error: \(error.localizedDescription)")
        }

        LibboxSetMemoryLimit(!SharedPreferences.disableMemoryLimit)

        commandServer = LibboxNewCommandServer(serverInterface(self), Int32(SharedPreferences.maxLogLines))
        do {
            try commandServer.start()
        } catch {
            writeFatalError("(packet-tunnel): log server start error: \(error.localizedDescription)")
            return
        }
        writeMessage("(packet-tunnel) log server started")

        startService()
    }

    private func writeMessage(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(message)
        } else {
            NSLog(message)
        }
    }

    private func writeError(_ message: String) {
        writeMessage(message)
        try? message.write(to: ExtensionProvider.errorFile, atomically: true, encoding: .utf8)
    }

    public func writeFatalError(_ message: String) {
        #if DEBUG
            NSLog(message)
        #endif
        writeError(message)
        cancelTunnelWithError(NSError(domain: message, code: 0))
    }

    private func startService() {
        let profile: Profile?
        do {
            profile = try ProfileManager.get(Int64(SharedPreferences.selectedProfileID))
        } catch {
            writeFatalError("(packet-tunnel) error: missing default profile: \(error.localizedDescription)")
            return
        }
        guard let profile else {
            writeFatalError("(packet-tunnel) error: missing default profile")
            return
        }
        let configContent: String
        do {
            configContent = try profile.read()
        } catch {
            writeFatalError("(packet-tunnel) error: read config file \(profile.path): \(error.localizedDescription)")
            return
        }
        var error: NSError?
        let service = LibboxNewService(configContent, ExtensionPlatformInterface(self, commandServer), &error)
        if let error {
            writeError("(packet-tunnel) error: create service: \(error.localizedDescription)")
            return
        }
        guard let service else {
            return
        }
        do {
            try service.start()
        } catch {
            writeError("(packet-tunnel) error: start service: \(error.localizedDescription)")
            return
        }
        boxService = service
        commandServer.setService(service)
        #if os(macOS)
            Task.detached {
                SharedPreferences.startedByUser = true
            }
        #endif
    }

    private func stopService() {
        if let service = boxService {
            do {
                try service.close()
            } catch {
                writeError("(packet-tunnel) error: stop service: \(error.localizedDescription)")
            }
            boxService = nil
            commandServer.setService(nil)
        }
    }

    private func reloadService() {
        writeMessage("(packet-tunnel) reloading service")
        reasserting = true
        defer {
            reasserting = false
        }
        stopService()
        startService()
    }

    override open func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            try? server.close()
            commandServer = nil
        }
        #if os(macOS)
            if reason == .userInitiated {
                SharedPreferences.startedByUser = reason == .userInitiated
            }
        #endif
    }

    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        messageData
    }

    override open func sleep() async {
        if let boxService {
            boxService.sleep()
        }
    }

    override open func wake() {
        if let boxService {
            boxService.wake()
        }
    }

    private class serverInterface: NSObject, LibboxCommandServerHandlerProtocol {
        unowned let tunnel: ExtensionProvider

        init(_ tunnel: ExtensionProvider) {
            self.tunnel = tunnel
            super.init()
        }

        func serviceReload() throws {
            tunnel.reloadService()
        }

        func serviceStop() throws {
            tunnel.stopService()
            tunnel.writeMessage("(packet-tunnel) debug: service stopped")
        }
    }
}
