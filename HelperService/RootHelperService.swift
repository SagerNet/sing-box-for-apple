import Foundation
import Library
import os

private let logger = Logger(category: "RootHelper")

class RootHelperService: NSObject {
    private var listener: NSXPCListener?

    func start() {
        listener = NSXPCListener(machServiceName: AppConfiguration.rootHelperMachService)
        listener?.delegate = self
        listener?.resume()
    }
}

extension RootHelperService: NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let systemExtensionID = AppConfiguration.systemExtensionBundleID
        let standaloneID = AppConfiguration.packageName + ".standalone"
        let teamID = AppConfiguration.teamID
        let requirement = "(identifier \"\(systemExtensionID)\" or identifier \"\(standaloneID)\") and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        do {
            try newConnection.setCodeSigningRequirement(requirement)
        } catch {
            logger.warning("Rejected XPC connection: \(error.localizedDescription)")
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

    func getVersion(reply: @escaping (String) -> Void) {
        reply(Bundle.main.version)
    }
}
