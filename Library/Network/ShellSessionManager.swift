#if os(macOS) || JAILBREAK
    import Foundation
    import Libbox
    import os

    private let logger = Logger(category: "ShellSessionManager")

    public final class ShellSessionManager {
        private let resolveShell: (String) -> String
        private let resolveHomeDirectory: (String) -> String

        private var sessions: [String: any LibboxShellSessionProtocol] = [:]
        private var sessionsByOwner: [ObjectIdentifier: Set<String>] = [:]
        private var ownerBySession: [String: ObjectIdentifier] = [:]
        private let access = NSLock()

        public init(
            resolveShell: @escaping (String) -> String = { $0 },
            resolveHomeDirectory: @escaping (String) -> String = { $0 }
        ) {
            self.resolveShell = resolveShell
            self.resolveHomeDirectory = resolveHomeDirectory
        }

        public func open(
            owner: ObjectIdentifier,
            user: PlatformUserPayload,
            command: String,
            environ: [String],
            term: String,
            rows: Int32,
            cols: Int32
        ) throws -> (FileHandle, String) {
            let shell = resolveShell(user.shell)
            let homeDirectory = resolveHomeDirectory(user.homeDir)
            logger.info("open: user=\(user.username, privacy: .public), shell=\(shell, privacy: .public), term=\(term, privacy: .public), rows=\(rows), cols=\(cols)")

            let argv: [String]
            if command.isEmpty {
                argv = ["-\((shell as NSString).lastPathComponent)"]
            } else {
                argv = [shell, "-c", command]
            }
            let groupValues = user.groups.map(\.int32Value)

            var error: NSError?
            let session: (any LibboxShellSessionProtocol)?
            if term.isEmpty {
                session = LibboxOpenNativePipeSession(
                    shell, homeDirectory,
                    argv.toStringIterator(), environ.toStringIterator(),
                    user.uid, user.gid, groupValues.toInt32Iterator(),
                    &error
                )
            } else {
                session = LibboxOpenNativeShellSession(
                    shell, homeDirectory,
                    argv.toStringIterator(), environ.toStringIterator(),
                    term, rows, cols,
                    user.uid, user.gid, groupValues.toInt32Iterator(),
                    &error
                )
            }
            guard let session else {
                throw error ?? Self.error("spawn shell session failed")
            }

            let masterFD = dup(session.masterFD())
            if masterFD < 0 {
                let dupErrno = errno
                try? session.close()
                throw NSError(domain: "ShellSessionManager", code: Int(dupErrno), userInfo: [
                    NSLocalizedDescriptionKey: "dup master fd: \(String(cString: strerror(dupErrno)))",
                ])
            }

            let handle = UUID().uuidString
            access.lock()
            sessions[handle] = session
            sessionsByOwner[owner, default: []].insert(handle)
            ownerBySession[handle] = owner
            access.unlock()

            return (FileHandle(fileDescriptor: masterFD, closeOnDealloc: true), handle)
        }

        public func signal(handle: String, signal: Int32) throws {
            try requireSession(handle).signal(signal)
        }

        public func wait(handle: String) throws -> Int32 {
            let session = try requireSession(handle)
            defer { forget(handle) }
            var exitStatus: Int32 = 0
            try session.waitExit(&exitStatus)
            logger.info("wait: handle \(handle, privacy: .public) exited with status \(exitStatus)")
            return exitStatus
        }

        public func close(handle: String) throws {
            access.lock()
            let session = sessions.removeValue(forKey: handle)
            forgetOwnerLocked(handle)
            access.unlock()
            try session?.close()
        }

        public func reap(owner: ObjectIdentifier) {
            access.lock()
            let handles = sessionsByOwner.removeValue(forKey: owner) ?? []
            var reaped: [(String, any LibboxShellSessionProtocol)] = []
            for handle in handles {
                ownerBySession.removeValue(forKey: handle)
                if let session = sessions.removeValue(forKey: handle) {
                    reaped.append((handle, session))
                }
            }
            access.unlock()
            if reaped.isEmpty {
                return
            }
            logger.info("reap: client gone, reaping \(reaped.count) shell session(s)")
            for (handle, session) in reaped {
                do {
                    try session.close()
                } catch {
                    logger.error("reap: handle \(handle, privacy: .public) close failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func requireSession(_ handle: String) throws -> any LibboxShellSessionProtocol {
            access.lock()
            defer { access.unlock() }
            guard let session = sessions[handle] else {
                throw Self.error("shell session not found: \(handle)")
            }
            return session
        }

        private func forget(_ handle: String) {
            access.lock()
            sessions.removeValue(forKey: handle)
            forgetOwnerLocked(handle)
            access.unlock()
        }

        private func forgetOwnerLocked(_ handle: String) {
            guard let owner = ownerBySession.removeValue(forKey: handle) else { return }
            guard var handles = sessionsByOwner[owner] else { return }
            handles.remove(handle)
            if handles.isEmpty {
                sessionsByOwner.removeValue(forKey: owner)
            } else {
                sessionsByOwner[owner] = handles
            }
        }

        private static func error(_ message: String) -> NSError {
            NSError(domain: "ShellSessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
#endif
