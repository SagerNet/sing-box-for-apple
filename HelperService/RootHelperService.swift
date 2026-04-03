import Foundation
import Libbox
import Library
import Network
import os

private let logger = Logger(category: "RootHelper")

private class NeighborGoListener: NSObject, LibboxNeighborUpdateListenerProtocol {
    private weak var service: RootHelperService?

    init(service: RootHelperService) {
        self.service = service
    }

    func updateNeighborTable(_ entries: (any LibboxNeighborEntryIteratorProtocol)?) {
        guard let entries, let service else { return }
        service.pushNeighborTable(entries: entries)
    }
}

class RootHelperService: NSObject {
    private var listener: NSXPCListener?
    private var neighborSubscription: LibboxNeighborSubscription?
    private var neighborCallbackConnection: NSXPCConnection?
    private var neighborLeaseWatcher: DispatchSourceFileSystemObject?
    private var pathMonitor: NWPathMonitor?
    private var pendingNATFlush: DispatchWorkItem?
    private var tunInterfaceName: String?
    var pendingCrashLogs: [CrashLogFileResult] = []

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

    func startNeighborMonitor(callbackEndpoint: NSXPCListenerEndpoint, reply: @escaping (NSError?) -> Void) {
        logger.info("startNeighborMonitor")
        closeNeighborMonitorInternal()

        let callbackConnection = NSXPCConnection(listenerEndpoint: callbackEndpoint)
        let listenerInterface = NSXPCInterface(with: NeighborTableListenerProtocol.self)
        RootHelperXPC.configureListenerInterface(listenerInterface)
        callbackConnection.remoteObjectInterface = listenerInterface
        callbackConnection.resume()
        neighborCallbackConnection = callbackConnection

        let goListener = NeighborGoListener(service: self)
        var error: NSError?
        let subscription = LibboxSubscribeNeighborTable(goListener, &error)
        if let error {
            logger.error("startNeighborMonitor: \(error.localizedDescription)")
            callbackConnection.invalidate()
            neighborCallbackConnection = nil
            reply(error)
            return
        }
        neighborSubscription = subscription
        startLeaseFileWatcher()
        startNATCleaner()
        reply(nil)
    }

    func registerMyInterface(name: String, reply: @escaping (NSError?) -> Void) {
        logger.info("registerMyInterface: \(name)")
        tunInterfaceName = name
        flushInternetSharingNAT()
        reply(nil)
    }

    static func readCrashLogFiles() -> [CrashLogFileResult] {
        var results: [CrashLogFileResult] = []

        let crashLogSearchPaths: [(directory: String, fileNames: [String])] = [
            (WorkingDirectoryManager.extensionWorkingDirectoryPath, [
                "CrashReport-NetworkExtension.log",
                "CrashReport-NetworkExtension.log.old",
            ]),
            (WorkingDirectoryManager.helperWorkingDirectoryPath, [
                "CrashReport-RootHelper.log",
                "CrashReport-RootHelper.log.old",
            ]),
            (WorkingDirectoryManager.extensionBasePath, [
                "configuration.json",
            ]),
            (WorkingDirectoryManager.helperBasePath, [
                "configuration.json",
            ]),
        ]

        for searchPath in crashLogSearchPaths {
            for fileName in searchPath.fileNames {
                let filePath = (searchPath.directory as NSString).appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: filePath),
                      let content = try? String(contentsOfFile: filePath, encoding: .utf8),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    continue
                }

                let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
                let modificationDate = (attrs?[.modificationDate] as? Date) ?? Date()

                results.append(CrashLogFileResult(
                    fileName: fileName,
                    content: content,
                    modificationDate: modificationDate
                ))

                try? FileManager.default.removeItem(atPath: filePath)
            }
        }

        return results
    }

    func collectAllCrashArtifacts(reply: @escaping (CrashArtifactsResult?, NSError?) -> Void) {
        let result = CrashArtifactsResult()

        var crashLogs = pendingCrashLogs
        pendingCrashLogs.removeAll()
        crashLogs.append(contentsOf: Self.readCrashLogFiles())
        result.crashLogs = crashLogs

        result.helperNativeCrashData = NativeCrashReporter.loadAndPurgePendingCrashReportData()

        let extensionReportURL = CrashReportArchive.pendingNativeCrashReportURL(
            basePath: URL(fileURLWithPath: WorkingDirectoryManager.extensionNativeCrashBasePath, isDirectory: true),
            bundleIdentifier: AppConfiguration.systemExtensionBundleID
        )
        if let data = try? Data(contentsOf: extensionReportURL), !data.isEmpty {
            result.extensionNativeCrashData = data
            try? FileManager.default.removeItem(at: extensionReportURL)
        }

        reply(result, nil)
    }

    func collectOOMReportArtifacts(reply: @escaping (OOMReportArtifactsResult?, NSError?) -> Void) {
        let result = OOMReportArtifactsResult()
        let oomReportsPath = WorkingDirectoryManager.extensionOOMReportsPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: oomReportsPath),
              let entries = try? fm.contentsOfDirectory(atPath: oomReportsPath)
        else {
            reply(result, nil)
            return
        }

        for entry in entries {
            let dirPath = (oomReportsPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            guard let fileNames = try? fm.contentsOfDirectory(atPath: dirPath) else {
                continue
            }

            var files: [OOMReportFileResult] = []
            for fileName in fileNames {
                let filePath = (dirPath as NSString).appendingPathComponent(fileName)
                guard let data = fm.contents(atPath: filePath) else {
                    continue
                }
                files.append(OOMReportFileResult(name: fileName, data: data))
            }

            if !files.isEmpty {
                result.reports.append(OOMReportDirectoryResult(directoryName: entry, files: files))
            }

            try? fm.removeItem(atPath: dirPath)
        }

        reply(result, nil)
    }

    func triggerGoCrash(reply: @escaping (NSError?) -> Void) {
        reply(nil)
        LibboxTriggerGoPanic()
    }

    func triggerNativeCrash(reply: @escaping (NSError?) -> Void) {
        reply(nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            fatalError("debug native crash")
        }
    }

    func closeNeighborMonitor(reply: @escaping (NSError?) -> Void) {
        logger.info("closeNeighborMonitor")
        closeNeighborMonitorInternal()
        reply(nil)
    }

    private func closeNeighborMonitorInternal() {
        neighborSubscription?.close()
        neighborSubscription = nil
        neighborLeaseWatcher?.cancel()
        neighborLeaseWatcher = nil
        pendingNATFlush?.cancel()
        pendingNATFlush = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        tunInterfaceName = nil
        neighborCallbackConnection?.invalidate()
        neighborCallbackConnection = nil
    }

    func pushNeighborTable(entries: LibboxNeighborEntryIteratorProtocol) {
        guard let callbackConnection = neighborCallbackConnection else {
            logger.warning("pushNeighborTable: no callback connection")
            return
        }
        guard let proxy = callbackConnection.remoteObjectProxyWithErrorHandler({ error in
            logger.error("pushNeighborTable XPC error: \(error.localizedDescription)")
        }) as? NeighborTableListenerProtocol else {
            logger.warning("pushNeighborTable: failed to get proxy")
            return
        }

        let leaseIterator = LibboxReadBootpdLeases()
        var leaseEntries: [NeighborEntryResult] = []
        var leaseHostnamesByMAC: [String: String] = [:]
        var leaseHostnamesByIP: [String: String] = [:]
        if let leaseIterator {
            while leaseIterator.hasNext() {
                guard let entry = leaseIterator.next() else { continue }
                leaseEntries.append(NeighborEntryResult(
                    address: entry.address,
                    macAddress: entry.macAddress,
                    hostname: entry.hostname
                ))
                if !entry.hostname.isEmpty {
                    leaseHostnamesByMAC[entry.macAddress] = entry.hostname
                    leaseHostnamesByIP[entry.address] = entry.hostname
                }
            }
        }
        logger.debug("pushNeighborTable: leases=\(leaseEntries.count), hostnames=\(leaseHostnamesByMAC.count)")

        var results: [NeighborEntryResult] = []
        var seenAddresses: Set<String> = []
        while entries.hasNext() {
            guard let entry = entries.next() else { continue }
            seenAddresses.insert(entry.address)
            var hostname = entry.hostname
            if hostname.isEmpty {
                hostname = leaseHostnamesByIP[entry.address] ?? leaseHostnamesByMAC[entry.macAddress] ?? ""
            }
            results.append(NeighborEntryResult(
                address: entry.address,
                macAddress: entry.macAddress,
                hostname: hostname
            ))
        }
        for leaseEntry in leaseEntries {
            if !seenAddresses.contains(leaseEntry.address) {
                results.append(leaseEntry)
            }
        }
        logger.debug("pushNeighborTable: \(results.count) entries")
        proxy.updateNeighborTable(entries: results as NSArray)
    }

    private func startNATCleaner() {
        flushInternetSharingNAT()
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "nat-cleaner")
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            logger.debug("NATCleaner: path update, status=\(String(describing: path.status)), interfaces=\(path.availableInterfaces.map(\.name))")
            self.pendingNATFlush?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushInternetSharingNAT()
            }
            self.pendingNATFlush = workItem
            queue.asyncAfter(deadline: .now() + 2, execute: workItem)
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func flushInternetSharingNAT() {
        guard let tunName = tunInterfaceName, !tunName.isEmpty else {
            logger.debug("flushInternetSharingNAT: no tun interface name set")
            return
        }
        let anchors = [
            "com.apple.internet-sharing/shared_v4",
            "com.apple.internet-sharing/shared_v6",
        ]
        let filter = " on \(tunName) "
        for anchor in anchors {
            removeNATRulesForInterface(anchor: anchor, filter: filter)
        }
    }

    private func removeNATRulesForInterface(anchor: String, filter: String) {
        let readProcess = Process()
        readProcess.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        readProcess.arguments = ["-a", anchor, "-s", "nat"]
        let readPipe = Pipe()
        readProcess.standardOutput = readPipe
        readProcess.standardError = FileHandle.nullDevice
        do {
            try readProcess.run()
        } catch {
            logger.error("removeNATRules: failed to read \(anchor): \(error.localizedDescription)")
            return
        }
        let output = String(data: readPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        readProcess.waitUntilExit()
        if readProcess.terminationStatus != 0 {
            logger.warning("removeNATRules: pfctl -s nat exited with \(readProcess.terminationStatus) for \(anchor)")
            return
        }
        if output.isEmpty {
            logger.debug("removeNATRules: \(anchor) has no NAT rules")
            return
        }
        guard output.contains(filter) else {
            logger.debug("removeNATRules: \(anchor) has no rules matching \(filter)")
            return
        }
        let lines = output.components(separatedBy: "\n")
        let removed = lines.filter { $0.contains(filter) }
        let remaining = lines.filter { !$0.contains(filter) }.joined(separator: "\n")
        logger.info("removeNATRules: \(anchor): removing \(removed.count) rules matching \(filter), keeping \(lines.count - removed.count) rules")
        for rule in removed {
            logger.debug("removeNATRules: removing: \(rule)")
        }
        let writeProcess = Process()
        writeProcess.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        writeProcess.arguments = ["-a", anchor, "-N", "-f", "-"]
        let writePipe = Pipe()
        writePipe.fileHandleForWriting.write(remaining.data(using: .utf8) ?? Data())
        writePipe.fileHandleForWriting.closeFile()
        writeProcess.standardInput = writePipe
        writeProcess.standardOutput = FileHandle.nullDevice
        let writeErrorPipe = Pipe()
        writeProcess.standardError = writeErrorPipe
        do {
            try writeProcess.run()
        } catch {
            logger.error("removeNATRules: failed to write \(anchor): \(error.localizedDescription)")
            return
        }
        let stderrData = writeErrorPipe.fileHandleForReading.readDataToEndOfFile()
        writeProcess.waitUntilExit()
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
        if writeProcess.terminationStatus != 0 {
            logger.error("removeNATRules: pfctl -f exited with \(writeProcess.terminationStatus) for \(anchor), stderr: \(stderrOutput)")
        } else {
            logger.debug("removeNATRules: successfully updated \(anchor)")
        }
    }

    private func startLeaseFileWatcher() {
        let leasePath = "/var/db/dhcpd_leases"
        let fd = open(leasePath, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("startLeaseFileWatcher: failed to open \(leasePath), errno=\(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global()
        )
        source.setEventHandler { [weak self] in
            guard let self, neighborSubscription != nil else { return }
            guard let callbackConnection = neighborCallbackConnection else { return }
            guard let proxy = callbackConnection.remoteObjectProxyWithErrorHandler({ error in
                logger.error("leaseWatcher push error: \(error.localizedDescription)")
            }) as? NeighborTableListenerProtocol else {
                return
            }

            let leaseIterator = LibboxReadBootpdLeases()
            var results: [NeighborEntryResult] = []
            if let leaseIterator {
                while leaseIterator.hasNext() {
                    guard let entry = leaseIterator.next() else { continue }
                    results.append(NeighborEntryResult(
                        address: entry.address,
                        macAddress: entry.macAddress,
                        hostname: entry.hostname
                    ))
                }
            }
            proxy.updateNeighborTable(entries: results as NSArray)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        neighborLeaseWatcher = source
    }
}
