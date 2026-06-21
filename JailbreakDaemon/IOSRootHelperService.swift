import Foundation
import Library
import os

private let logger = Logger(category: "RootHelper")

private func resolveShell(_ hint: String) -> String {
    let fileManager = FileManager.default
    if !hint.isEmpty, fileManager.isExecutableFile(atPath: hint) {
        return hint
    }
    for candidate in JailbreakConfiguration.shellCandidates where fileManager.isExecutableFile(atPath: candidate) {
        return candidate
    }
    return "/bin/sh"
}

private func resolveHomeDirectory(_ hint: String) -> String {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if !hint.isEmpty, fileManager.fileExists(atPath: hint, isDirectory: &isDirectory), isDirectory.boolValue {
        return hint
    }
    for candidate in ["/var/root", "/var/mobile", "/"] where fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue {
        return candidate
    }
    return "/"
}

final class IOSRootHelperService: NSObject {
    private var listener: NSXPCListener?
    private let shellSessionManager = ShellSessionManager(
        resolveShell: resolveShell,
        resolveHomeDirectory: resolveHomeDirectory
    )

    func start() {
        let machListener = XPCMachServiceBridge.makeListener(machServiceName: AppConfiguration.rootHelperMachService)
        machListener.delegate = self
        machListener.resume()
        listener = machListener
        logger.info("listening on \(AppConfiguration.rootHelperMachService, privacy: .public)")
    }
}

extension IOSRootHelperService: NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // No peer check: the mach service is reachable only by processes holding the
        // mach-lookup global-name exception, which on the device is only our extension.
        let exportedInterface = NSXPCInterface(with: ShellHelperProtocol.self)
        ShellHelperXPC.configureInterface(exportedInterface)
        newConnection.exportedInterface = exportedInterface
        newConnection.exportedObject = self
        let owner = ObjectIdentifier(newConnection)
        newConnection.invalidationHandler = { [weak self] in
            self?.shellSessionManager.reap(owner: owner)
        }
        newConnection.resume()
        return true
    }
}

extension IOSRootHelperService: ShellHelperProtocol {
    func getVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.version)
    }

    func findConnectionOwner(
        ipProtocol: Int32,
        sourceAddress: String,
        sourcePort: Int32,
        destinationAddress: String,
        destinationPort: Int32,
        reply: @escaping (ConnectionOwnerResult?, NSError?) -> Void
    ) {
        guard let result = ConnectionOwnerLookup.find(
            ipProtocol: ipProtocol,
            sourceAddress: sourceAddress,
            sourcePort: sourcePort,
            destinationAddress: destinationAddress,
            destinationPort: destinationPort
        ) else {
            reply(nil, NSError(domain: "RootHelper", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Connection owner not found",
            ]))
            return
        }
        reply(ConnectionOwnerResult(
            userId: result.userId,
            userName: result.userName,
            processPath: result.processPath
        ), nil)
    }

    func openShellSession(
        user: PlatformUserPayload,
        command: String,
        environ: NSArray,
        term: String,
        rows: Int32,
        cols: Int32,
        reply: @escaping (FileHandle?, String?, NSError?) -> Void
    ) {
        guard let currentConnection = NSXPCConnection.current() else {
            reply(nil, nil, NSError(domain: "RootHelper", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "no current XPC connection",
            ]))
            return
        }
        do {
            let (fileHandle, handle) = try shellSessionManager.open(
                owner: ObjectIdentifier(currentConnection),
                user: user,
                command: command,
                environ: environ.compactMap { $0 as? String },
                term: term,
                rows: rows,
                cols: cols
            )
            reply(fileHandle, handle, nil)
        } catch {
            logger.error("openShellSession: \(error.localizedDescription, privacy: .public)")
            reply(nil, nil, error as NSError)
        }
    }

    func signalShellSession(handle: String, signal sig: Int32, reply: @escaping (NSError?) -> Void) {
        do {
            try shellSessionManager.signal(handle: handle, signal: sig)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func waitShellSession(handle: String, reply: @escaping (Int32, NSError?) -> Void) {
        DispatchQueue.global().async { [weak self] in
            guard let self else {
                reply(255, NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "service deallocated",
                ]))
                return
            }
            do {
                let exitStatus = try shellSessionManager.wait(handle: handle)
                reply(exitStatus, nil)
            } catch {
                logger.error("waitShellSession: handle \(handle, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                reply(255, error as NSError)
            }
        }
    }

    func closeShellSession(handle: String, reply: @escaping (NSError?) -> Void) {
        do {
            try shellSessionManager.close(handle: handle)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func readSystemSSHHostKey(reply: @escaping (NSString?, NSError?) -> Void) {
        do {
            let keyData = try String(contentsOfFile: JailbreakConfiguration.systemSSHHostKeyPath, encoding: .utf8)
            reply(keyData as NSString, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}
