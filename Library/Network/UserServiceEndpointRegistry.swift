#if os(macOS)
    import Foundation

    final class UserServiceEndpointRegistry {
        static let shared = UserServiceEndpointRegistry()

        private let lock = NSLock()
        private var endpoint: NSXPCListenerEndpoint?

        func update(_ endpoint: NSXPCListenerEndpoint) {
            lock.lock()
            self.endpoint = endpoint
            lock.unlock()
        }

        func clear() {
            lock.lock()
            endpoint = nil
            lock.unlock()
        }

        func get() -> NSXPCListenerEndpoint? {
            lock.lock()
            defer { lock.unlock() }
            return endpoint
        }
    }
#endif
