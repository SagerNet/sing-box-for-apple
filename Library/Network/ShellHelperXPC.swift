#if os(macOS) || JAILBREAK
    import Foundation
    import Libbox
    import os

    @objc(PlatformUserPayload) public class PlatformUserPayload: NSObject, NSSecureCoding {
        public static let supportsSecureCoding = true

        @objc public var username: String
        @objc public var uid: Int32
        @objc public var gid: Int32
        @objc public var homeDir: String
        @objc public var shell: String
        @objc public var groups: [NSNumber]

        public init(username: String, uid: Int32, gid: Int32, homeDir: String, shell: String, groups: [Int32]) {
            self.username = username
            self.uid = uid
            self.gid = gid
            self.homeDir = homeDir
            self.shell = shell
            self.groups = groups.map { NSNumber(value: $0) }
        }

        public required init?(coder: NSCoder) {
            guard let username = coder.decodeObject(of: NSString.self, forKey: "username") as String?,
                  let homeDir = coder.decodeObject(of: NSString.self, forKey: "homeDir") as String?,
                  let shell = coder.decodeObject(of: NSString.self, forKey: "shell") as String?
            else {
                return nil
            }
            self.username = username
            self.homeDir = homeDir
            self.shell = shell
            uid = coder.decodeInt32(forKey: "uid")
            gid = coder.decodeInt32(forKey: "gid")
            let groupClasses = [NSArray.self, NSNumber.self] as [AnyClass]
            groups = coder.decodeObject(of: groupClasses, forKey: "groups") as? [NSNumber] ?? []
        }

        public func encode(with coder: NSCoder) {
            coder.encode(username as NSString, forKey: "username")
            coder.encode(uid, forKey: "uid")
            coder.encode(gid, forKey: "gid")
            coder.encode(homeDir as NSString, forKey: "homeDir")
            coder.encode(shell as NSString, forKey: "shell")
            coder.encode(groups as NSArray, forKey: "groups")
        }
    }

    @objc public protocol ShellHelperProtocol {
        func getVersion(reply: @escaping (String) -> Void)
        func openShellSession(
            user: PlatformUserPayload,
            command: String,
            environ: NSArray,
            term: String,
            rows: Int32,
            cols: Int32,
            reply: @escaping (FileHandle?, String?, NSError?) -> Void
        )
        func signalShellSession(handle: String, signal: Int32, reply: @escaping (NSError?) -> Void)
        func waitShellSession(handle: String, reply: @escaping (Int32, NSError?) -> Void)
        func closeShellSession(handle: String, reply: @escaping (NSError?) -> Void)
        func readSystemSSHHostKey(reply: @escaping (NSString?, NSError?) -> Void)
    }

    public enum ShellHelperXPC {
        public static func configureInterface(_ interface: NSXPCInterface) {
            let openShellSelector = #selector(ShellHelperProtocol.openShellSession(user:command:environ:term:rows:cols:reply:))
            let userPayloadClasses = NSSet(array: [PlatformUserPayload.self, NSArray.self, NSNumber.self, NSString.self]) as! Set<AnyHashable>
            interface.setClasses(
                userPayloadClasses,
                for: openShellSelector,
                argumentIndex: 0,
                ofReply: false
            )
            let shellEnvClasses = NSSet(array: [NSArray.self, NSString.self]) as! Set<AnyHashable>
            interface.setClasses(
                shellEnvClasses,
                for: openShellSelector,
                argumentIndex: 2,
                ofReply: false
            )
        }
    }

    struct ShellSessionHandshake {
        let fileHandle: FileHandle
        let handle: String
    }

    public final class ShellHelperClient: MachServiceClient {
        public static let shared = ShellHelperClient()

        private init() {
            let interface = NSXPCInterface(with: ShellHelperProtocol.self)
            ShellHelperXPC.configureInterface(interface)
            super.init(
                machServiceName: AppConfiguration.rootHelperMachService,
                remoteInterface: interface,
                logger: Logger(category: "ShellHelperClient")
            )
        }

        public func getVersion() throws -> String {
            try call("getVersion") { proxy, reply in
                (proxy as! ShellHelperProtocol).getVersion { reply($0 as String?, nil) }
            }
        }

        public func openShellSession(
            user: PlatformUserPayload,
            command: String,
            environ: [String],
            term: String,
            rows: Int32,
            cols: Int32
        ) throws -> (FileHandle, String) {
            let handshake: ShellSessionHandshake = try call("openShellSession", timeout: .seconds(10)) { proxy, reply in
                (proxy as! ShellHelperProtocol).openShellSession(
                    user: user,
                    command: command,
                    environ: environ as NSArray,
                    term: term,
                    rows: rows,
                    cols: cols
                ) { fileHandle, handle, error in
                    if let fileHandle, let handle {
                        reply(ShellSessionHandshake(fileHandle: fileHandle, handle: handle), error)
                    } else {
                        reply(nil, error)
                    }
                }
            }
            return (handshake.fileHandle, handshake.handle)
        }

        public func signalShellSession(handle: String, signal: Int32) throws {
            try callVoid("signalShellSession") { proxy, reply in
                (proxy as! ShellHelperProtocol).signalShellSession(handle: handle, signal: signal, reply: reply)
            }
        }

        public func waitShellSession(handle: String) throws -> Int32 {
            try call("waitShellSession", timeout: .never) { proxy, reply in
                (proxy as! ShellHelperProtocol).waitShellSession(handle: handle) { status, error in
                    reply(status, error)
                }
            }
        }

        public func closeShellSession(handle: String) throws {
            try callVoid("closeShellSession") { proxy, reply in
                (proxy as! ShellHelperProtocol).closeShellSession(handle: handle, reply: reply)
            }
        }

        public func readSystemSSHHostKey() throws -> String {
            try call("readSystemSSHHostKey") { proxy, reply in
                (proxy as! ShellHelperProtocol).readSystemSSHHostKey { keyData, error in
                    reply(keyData as String?, error)
                }
            }
        }
    }

    final class RootHelperShellSession: NSObject, LibboxShellSessionProtocol {
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
            try ShellHelperClient.shared.signalShellSession(handle: handle, signal: signal)
        }

        func waitExit(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
            let exitStatus = try ShellHelperClient.shared.waitShellSession(handle: handle)
            ret0_?.pointee = exitStatus
        }

        func close() throws {
            try? ShellHelperClient.shared.closeShellSession(handle: handle)
            fileHandle.closeFile()
        }
    }
#endif
