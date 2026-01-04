import Foundation
import Library
import os

private let logger = Logger(category: "RootHelper")

class RootHelperService: NSObject {
    private var listener: NSXPCListener?

    func start() {
        setupLogging()
        startXPCListener()
    }

    private func setupLogging() {
        let basePath = "/var/log/sing-box"
        try? FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        let logPath = basePath + "/roothelper.log"
        freopen(logPath, "a", stderr)
    }

    private func startXPCListener() {
        let machServiceName = getMachServiceName()
        listener = NSXPCListener(machServiceName: machServiceName)
        listener?.delegate = self
        listener?.resume()
    }

    private func getMachServiceName() -> String {
        if let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String {
            return "\(identifier).helper"
        }
        fatalError("Missing AppGroupIdentifier in Info.plist")
    }
}

extension RootHelperService: NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let allowedBundleIDs = [
            AppConfiguration.systemExtensionBundleID,
            AppConfiguration.packageName + ".standalone",
        ]
        guard XPCConnectionValidator.validateConnection(
            newConnection,
            teamID: AppConfiguration.teamID,
            allowedBundleIDs: allowedBundleIDs
        ) else {
            let info = XPCConnectionValidator.getConnectionInfo(newConnection)
            logger.warning("Rejected XPC connection: pid=\(info.pid), bundleID=\(info.bundleID ?? "unknown"), teamID=\(info.teamID ?? "unknown")")
            return false
        }

        let exportedInterface = NSXPCInterface(with: RootHelperProtocol.self)
        RootHelperXPC.configureInterface(exportedInterface)
        newConnection.exportedInterface = exportedInterface
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }
}

extension RootHelperService: RootHelperProtocol {
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
            let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Connection owner not found",
            ])
            logger.error("findConnectionOwner: \(error.localizedDescription)")
            reply(nil, error)
            return
        }

        let ownerResult = ConnectionOwnerResult(
            userId: result.userId,
            userName: result.userName,
            processPath: result.processPath
        )
        reply(ownerResult, nil)
    }

    func getWorkingDirectorySize(reply: @escaping (Int64, NSError?) -> Void) {
        let size = WorkingDirectoryManager.getSize()
        reply(size, nil)
    }

    func cleanWorkingDirectory(reply: @escaping (NSError?) -> Void) {
        do {
            try WorkingDirectoryManager.clean()
            reply(nil)
        } catch {
            logger.error("cleanWorkingDirectory error: \(error.localizedDescription)")
            reply(error as NSError)
        }
    }
}
