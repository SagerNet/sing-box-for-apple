#if os(macOS)
    import Foundation
    import os

    private let logger = Logger(category: "RootHelperXPC")

    @objc(NeighborEntryResult) public class NeighborEntryResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var address: String
        @objc public var macAddress: String
        @objc public var hostname: String

        public init(address: String, macAddress: String, hostname: String) {
            self.address = address
            self.macAddress = macAddress
            self.hostname = hostname
        }

        public required init?(coder: NSCoder) {
            address = coder.decodeObject(of: NSString.self, forKey: "address") as? String ?? ""
            macAddress = coder.decodeObject(of: NSString.self, forKey: "macAddress") as? String ?? ""
            hostname = coder.decodeObject(of: NSString.self, forKey: "hostname") as? String ?? ""
        }

        public func encode(with coder: NSCoder) {
            coder.encode(address as NSString, forKey: "address")
            coder.encode(macAddress as NSString, forKey: "macAddress")
            coder.encode(hostname as NSString, forKey: "hostname")
        }
    }

    @objc public protocol NeighborTableListenerProtocol {
        func updateNeighborTable(entries: NSArray)
    }

    @objc public class ConnectionOwnerResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var userId: Int32
        @objc public var userName: String
        @objc public var processPath: String

        public init(userId: Int32, userName: String, processPath: String) {
            self.userId = userId
            self.userName = userName
            self.processPath = processPath
        }

        public required init?(coder: NSCoder) {
            userId = coder.decodeInt32(forKey: "userId")
            userName = coder.decodeObject(of: NSString.self, forKey: "userName") as? String ?? ""
            processPath = coder.decodeObject(of: NSString.self, forKey: "processPath") as? String ?? ""
        }

        public func encode(with coder: NSCoder) {
            coder.encode(userId, forKey: "userId")
            coder.encode(userName as NSString, forKey: "userName")
            coder.encode(processPath as NSString, forKey: "processPath")
        }
    }

    @objc(CrashLogFileResult) public class CrashLogFileResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var fileName: String
        @objc public var content: String
        @objc public var modificationDate: Date

        public init(fileName: String, content: String, modificationDate: Date) {
            self.fileName = fileName
            self.content = content
            self.modificationDate = modificationDate
        }

        public required init?(coder: NSCoder) {
            fileName = coder.decodeObject(of: NSString.self, forKey: "fileName") as? String ?? ""
            content = coder.decodeObject(of: NSString.self, forKey: "content") as? String ?? ""
            modificationDate = coder.decodeObject(of: NSDate.self, forKey: "modificationDate") as? Date ?? Date()
        }

        public func encode(with coder: NSCoder) {
            coder.encode(fileName as NSString, forKey: "fileName")
            coder.encode(content as NSString, forKey: "content")
            coder.encode(modificationDate as NSDate, forKey: "modificationDate")
        }
    }

    @objc(CrashArtifactsResult) public class CrashArtifactsResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var crashLogs: [CrashLogFileResult] = []
        @objc public var helperNativeCrashData: Data?
        @objc public var extensionNativeCrashData: Data?

        override public init() {
            super.init()
        }

        public required init?(coder: NSCoder) {
            let logClasses = [NSArray.self, CrashLogFileResult.self] as [AnyClass]
            crashLogs = coder.decodeObject(of: logClasses, forKey: "crashLogs") as? [CrashLogFileResult] ?? []
            helperNativeCrashData = coder.decodeObject(of: NSData.self, forKey: "helperNativeCrashData") as? Data
            extensionNativeCrashData = coder.decodeObject(of: NSData.self, forKey: "extensionNativeCrashData") as? Data
        }

        public func encode(with coder: NSCoder) {
            coder.encode(crashLogs as NSArray, forKey: "crashLogs")
            coder.encode(helperNativeCrashData as NSData?, forKey: "helperNativeCrashData")
            coder.encode(extensionNativeCrashData as NSData?, forKey: "extensionNativeCrashData")
        }
    }

    @objc(OOMReportFileResult) public class OOMReportFileResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var name: String
        @objc public var data: Data

        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }

        public required init?(coder: NSCoder) {
            name = coder.decodeObject(of: NSString.self, forKey: "name") as? String ?? ""
            data = coder.decodeObject(of: NSData.self, forKey: "data") as? Data ?? Data()
        }

        public func encode(with coder: NSCoder) {
            coder.encode(name as NSString, forKey: "name")
            coder.encode(data as NSData, forKey: "data")
        }
    }

    @objc(OOMReportDirectoryResult) public class OOMReportDirectoryResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var directoryName: String
        @objc public var files: [OOMReportFileResult] = []

        public init(directoryName: String, files: [OOMReportFileResult]) {
            self.directoryName = directoryName
            self.files = files
        }

        public required init?(coder: NSCoder) {
            directoryName = coder.decodeObject(of: NSString.self, forKey: "directoryName") as? String ?? ""
            let fileClasses = [NSArray.self, OOMReportFileResult.self] as [AnyClass]
            files = coder.decodeObject(of: fileClasses, forKey: "files") as? [OOMReportFileResult] ?? []
        }

        public func encode(with coder: NSCoder) {
            coder.encode(directoryName as NSString, forKey: "directoryName")
            coder.encode(files as NSArray, forKey: "files")
        }
    }

    @objc(OOMReportArtifactsResult) public class OOMReportArtifactsResult: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var reports: [OOMReportDirectoryResult] = []

        override public init() {
            super.init()
        }

        public required init?(coder: NSCoder) {
            let reportClasses = [NSArray.self, OOMReportDirectoryResult.self] as [AnyClass]
            reports = coder.decodeObject(of: reportClasses, forKey: "reports") as? [OOMReportDirectoryResult] ?? []
        }

        public func encode(with coder: NSCoder) {
            coder.encode(reports as NSArray, forKey: "reports")
        }
    }

    @objc public protocol RootHelperProtocol {
        func findConnectionOwner(
            ipProtocol: Int32,
            sourceAddress: String,
            sourcePort: Int32,
            destinationAddress: String,
            destinationPort: Int32,
            reply: @escaping (ConnectionOwnerResult?, NSError?) -> Void
        )

        func getWorkingDirectorySize(reply: @escaping (Int64, NSError?) -> Void)
        func cleanWorkingDirectory(reply: @escaping (NSError?) -> Void)
        func getVersion(reply: @escaping (String) -> Void)
        func startNeighborMonitor(callbackEndpoint: NSXPCListenerEndpoint, reply: @escaping (NSError?) -> Void)
        func closeNeighborMonitor(reply: @escaping (NSError?) -> Void)
        func registerMyInterface(name: String, reply: @escaping (NSError?) -> Void)
        func collectAllCrashArtifacts(reply: @escaping (CrashArtifactsResult?, NSError?) -> Void)
        func collectOOMReportArtifacts(reply: @escaping (OOMReportArtifactsResult?, NSError?) -> Void)
        func promoteOOMDraft(reply: @escaping (NSError?) -> Void)
        func triggerGoCrash(reply: @escaping (NSError?) -> Void)
        func triggerNativeCrash(reply: @escaping (NSError?) -> Void)
    }

    public enum RootHelperXPC {
        public static func configureInterface(_ interface: NSXPCInterface) {
            let resultClasses = NSSet(array: [ConnectionOwnerResult.self, NSString.self]) as! Set<AnyHashable>
            interface.setClasses(
                resultClasses,
                for: #selector(RootHelperProtocol.findConnectionOwner(ipProtocol:sourceAddress:sourcePort:destinationAddress:destinationPort:reply:)),
                argumentIndex: 0,
                ofReply: true
            )
            let crashArtifactClasses = NSSet(array: [
                CrashArtifactsResult.self, NSArray.self, CrashLogFileResult.self, NSData.self,
            ]) as! Set<AnyHashable>
            interface.setClasses(
                crashArtifactClasses,
                for: #selector(RootHelperProtocol.collectAllCrashArtifacts(reply:)),
                argumentIndex: 0,
                ofReply: true
            )
            let oomArtifactClasses = NSSet(array: [
                OOMReportArtifactsResult.self, NSArray.self, OOMReportDirectoryResult.self, OOMReportFileResult.self, NSData.self,
            ]) as! Set<AnyHashable>
            interface.setClasses(
                oomArtifactClasses,
                for: #selector(RootHelperProtocol.collectOOMReportArtifacts(reply:)),
                argumentIndex: 0,
                ofReply: true
            )
            let endpointClasses = NSSet(array: [NSXPCListenerEndpoint.self]) as! Set<AnyHashable>
            interface.setClasses(
                endpointClasses,
                for: #selector(RootHelperProtocol.startNeighborMonitor(callbackEndpoint:reply:)),
                argumentIndex: 0,
                ofReply: false
            )
        }

        public static func configureListenerInterface(_ interface: NSXPCInterface) {
            let entryClasses = NSSet(array: [NSArray.self, NeighborEntryResult.self]) as! Set<AnyHashable>
            interface.setClasses(
                entryClasses,
                for: #selector(NeighborTableListenerProtocol.updateNeighborTable(entries:)),
                argumentIndex: 0,
                ofReply: false
            )
        }
    }

    public class RootHelperClient: @unchecked Sendable {
        public static let shared = RootHelperClient()

        private var connection: NSXPCConnection?
        private let connectionLock = NSLock()

        private init() {}

        private func getConnection() -> NSXPCConnection {
            connectionLock.lock()
            defer { connectionLock.unlock() }

            if let existing = connection {
                return existing
            }

            let newConnection = NSXPCConnection(machServiceName: AppConfiguration.rootHelperMachService)

            let remoteInterface = NSXPCInterface(with: RootHelperProtocol.self)
            RootHelperXPC.configureInterface(remoteInterface)
            newConnection.remoteObjectInterface = remoteInterface

            newConnection.invalidationHandler = { [weak self] in
                guard let self else { return }
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
            }

            newConnection.resume()
            connection = newConnection
            return newConnection
        }

        private func performXPCCallOptional<T>(
            _ operation: String,
            call: (RootHelperProtocol, @escaping (T?, NSError?) -> Void) -> Void
        ) throws -> T? {
            let semaphore = DispatchSemaphore(value: 0)
            var result: T?
            var resultError: NSError?

            let conn = getConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                logger.error("\(operation) XPC error: \(error.localizedDescription)")
                resultError = error as NSError
                semaphore.signal()
            }) as? RootHelperProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get RootHelper proxy",
                ])
            }

            call(proxy) { value, error in
                result = value
                resultError = error
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) request timeout",
                ])
                logger.error("\(operation): timeout")
                throw error
            }

            if let error = resultError {
                logger.error("\(operation) error: \(error.localizedDescription)")
                throw error
            }

            return result
        }

        private func performXPCCall<T>(
            _ operation: String,
            call: (RootHelperProtocol, @escaping (T?, NSError?) -> Void) -> Void
        ) throws -> T {
            guard let value: T = try performXPCCallOptional(operation, call: call) else {
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) returned nil",
                ])
            }
            return value
        }

        private func performXPCCallVoid(
            _ operation: String,
            call: (RootHelperProtocol, @escaping (NSError?) -> Void) -> Void
        ) throws {
            let semaphore = DispatchSemaphore(value: 0)
            var resultError: NSError?

            let conn = getConnection()
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                logger.error("\(operation) XPC error: \(error.localizedDescription)")
                resultError = error as NSError
                semaphore.signal()
            }) as? RootHelperProtocol else {
                connectionLock.lock()
                connection = nil
                connectionLock.unlock()
                conn.invalidate()
                throw NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get RootHelper proxy",
                ])
            }

            call(proxy) { error in
                resultError = error
                semaphore.signal()
            }

            let timeout = DispatchTime.now() + .seconds(5)
            if semaphore.wait(timeout: timeout) == .timedOut {
                let error = NSError(domain: "RootHelper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) request timeout",
                ])
                logger.error("\(operation): timeout")
                throw error
            }

            if let error = resultError {
                logger.error("\(operation) error: \(error.localizedDescription)")
                throw error
            }
        }

        public func findConnectionOwner(
            ipProtocol: Int32,
            sourceAddress: String,
            sourcePort: Int32,
            destinationAddress: String,
            destinationPort: Int32
        ) throws -> ConnectionOwnerResult {
            try performXPCCall("findConnectionOwner") { proxy, reply in
                proxy.findConnectionOwner(
                    ipProtocol: ipProtocol,
                    sourceAddress: sourceAddress,
                    sourcePort: sourcePort,
                    destinationAddress: destinationAddress,
                    destinationPort: destinationPort,
                    reply: reply
                )
            }
        }

        public func getWorkingDirectorySize() throws -> Int64 {
            try performXPCCall("getWorkingDirectorySize") { proxy, reply in
                proxy.getWorkingDirectorySize { size, error in
                    reply(size as Int64?, error)
                }
            }
        }

        public func cleanWorkingDirectory() throws {
            try performXPCCallVoid("cleanWorkingDirectory") { proxy, reply in
                proxy.cleanWorkingDirectory(reply: reply)
            }
        }

        public func startNeighborMonitor(callbackEndpoint: NSXPCListenerEndpoint) throws {
            try performXPCCallVoid("startNeighborMonitor") { proxy, reply in
                proxy.startNeighborMonitor(callbackEndpoint: callbackEndpoint, reply: reply)
            }
        }

        public func closeNeighborMonitor() throws {
            try performXPCCallVoid("closeNeighborMonitor") { proxy, reply in
                proxy.closeNeighborMonitor(reply: reply)
            }
        }

        public func registerMyInterface(name: String) throws {
            try performXPCCallVoid("registerMyInterface") { proxy, reply in
                proxy.registerMyInterface(name: name, reply: reply)
            }
        }

        public func collectAllCrashArtifacts() throws -> CrashArtifactsResult {
            try performXPCCall("collectAllCrashArtifacts") { proxy, reply in
                proxy.collectAllCrashArtifacts(reply: reply)
            }
        }

        public func collectOOMReportArtifacts() throws -> OOMReportArtifactsResult {
            try performXPCCall("collectOOMReportArtifacts") { proxy, reply in
                proxy.collectOOMReportArtifacts(reply: reply)
            }
        }

        public func promoteOOMDraft() throws {
            try performXPCCallVoid("promoteOOMDraft") { proxy, reply in
                proxy.promoteOOMDraft(reply: reply)
            }
        }

        public func triggerGoCrash() throws {
            try performXPCCallVoid("triggerGoCrash") { proxy, reply in
                proxy.triggerGoCrash(reply: reply)
            }
        }

        public func triggerNativeCrash() throws {
            try performXPCCallVoid("triggerNativeCrash") { proxy, reply in
                proxy.triggerNativeCrash(reply: reply)
            }
        }

        public func getVersion() throws -> String {
            try performXPCCall("getVersion") { proxy, reply in
                proxy.getVersion { version in
                    reply(version as String?, nil)
                }
            }
        }
    }
#endif
