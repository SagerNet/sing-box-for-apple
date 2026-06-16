import Foundation
import Libbox

public enum CommandTarget {
    private static let lock = NSLock()
    private static var activeRemoteServer: RemoteServer?
    /// One gRPC channel per remote session: standalone calls reuse it instead of
    /// paying a TCP+TLS handshake (and leaking the connection) on every action.
    private static var sharedRemoteClient: LibboxCommandClient?

    public static var remoteServer: RemoteServer? {
        lock.lock()
        defer { lock.unlock() }
        return activeRemoteServer
    }

    public static func setRemoteServer(_ server: RemoteServer?) {
        lock.lock()
        let previousClient = sharedRemoteClient
        sharedRemoteClient = nil
        activeRemoteServer = server
        lock.unlock()
        if let previousClient {
            try? previousClient.disconnect()
        }
    }

    public static var isRemote: Bool {
        remoteServer != nil
    }

    public static func libboxOptions(_ server: RemoteServer) -> LibboxRemoteConnectionOptions {
        let options = LibboxRemoteConnectionOptions()
        options.url = RemoteServer.connectURL(server.url)
        options.secret = server.secret
        return options
    }

    /// One-shot reachability probe for a draft (unsaved) server. Dials over the network
    /// and blocks until the probe completes, so it must run off the main thread.
    public static func probe(url: String, secret: String) -> Bool {
        let options = LibboxRemoteConnectionOptions()
        options.url = RemoteServer.connectURL(url)
        options.secret = secret
        var error: NSError?
        guard let client = LibboxNewStandaloneRemoteCommandClient(options, &error), error == nil else {
            return false
        }
        defer { try? client.disconnect() }
        var startedAt: Int64 = 0
        do {
            try client.getStartedAt(&startedAt)
            return true
        } catch {
            return false
        }
    }

    /// Returns a client for one-shot calls and streamed sessions. In remote mode the
    /// client is shared for the whole session — callers must not disconnect it.
    public static func standaloneClient() throws -> LibboxCommandClient {
        lock.lock()
        defer { lock.unlock() }
        guard let server = activeRemoteServer else {
            return LibboxNewStandaloneCommandClient()!
        }
        if let client = sharedRemoteClient {
            return client
        }
        let client = try newStandaloneClient(for: server)
        sharedRemoteClient = client
        return client
    }

    /// Returns a dedicated client owned by the caller, who is responsible for
    /// disconnecting it (e.g. the SSH terminal closes its client on session end).
    public static func ownedStandaloneClient() throws -> LibboxCommandClient {
        if let server = remoteServer {
            return try newStandaloneClient(for: server)
        }
        return LibboxNewStandaloneCommandClient()!
    }

    private static func newStandaloneClient(for server: RemoteServer) throws -> LibboxCommandClient {
        var error: NSError?
        let client = LibboxNewStandaloneRemoteCommandClient(libboxOptions(server), &error)
        if let error {
            throw error
        }
        return client!
    }
}
