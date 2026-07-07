#if os(macOS) || JAILBREAK
    import Foundation
    import Libbox
    import os

    private let logger = Logger(category: "BridgeSessionManager")

    public final class BridgeSessionManager {
        private var sessionsByHandle: [String: any LibboxBridgeSessionProtocol] = [:]
        private var handlesByOwner: [ObjectIdentifier: Set<String>] = [:]
        private let access = NSLock()

        public init() {}

        public func create(owner: ObjectIdentifier, options: LibboxBridgeOptions) throws -> (String, any LibboxBridgeSessionProtocol) {
            var error: NSError?
            guard let session = LibboxNewBridgeService(options, &error) else {
                throw error ?? NSError(domain: "BridgeSessionManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "create bridge service failed",
                ])
            }
            let handle = UUID().uuidString
            access.lock()
            sessionsByHandle[handle] = session
            handlesByOwner[owner, default: []].insert(handle)
            access.unlock()
            return (handle, session)
        }

        public func session(handle: String) -> (any LibboxBridgeSessionProtocol)? {
            access.lock()
            defer { access.unlock() }
            return sessionsByHandle[handle]
        }

        public func close(owner: ObjectIdentifier, handle: String) {
            access.lock()
            let session = sessionsByHandle.removeValue(forKey: handle)
            handlesByOwner[owner]?.remove(handle)
            access.unlock()
            if let session {
                try? session.close()
            }
        }

        public func reap(owner: ObjectIdentifier) {
            access.lock()
            let handles = handlesByOwner.removeValue(forKey: owner) ?? []
            let sessions = handles.compactMap { sessionsByHandle.removeValue(forKey: $0) }
            access.unlock()
            for session in sessions {
                logger.info("closing bridge \(session.name(), privacy: .public)")
                try? session.close()
            }
        }
    }
#endif
