import Foundation
import Libbox

public struct TaildropTargetPeer: Identifiable, Sendable {
    public let stableID: String
    public let name: String
    public let os: String

    public var id: String {
        stableID
    }
}

public struct TaildropTargetEndpoint: Identifiable, Sendable {
    public let endpointTag: String
    public let networkName: String
    public let peers: [TaildropTargetPeer]

    public var id: String {
        endpointTag
    }
}

public struct TaildropTargetList: Sendable {
    public let endpoints: [TaildropTargetEndpoint]
    public let hasRunningEndpoint: Bool
    public let hasSharingEndpoint: Bool
}

public enum TaildropTargets {
    public static func fetch() async throws -> TaildropTargetList {
        let session = SnapshotSession()
        defer {
            session.close()
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.expect(continuation)
            Task.detached {
                do {
                    try session.attach(CommandTarget.standaloneClient().subscribeTailscaleStatus(session))
                } catch {
                    session.finish(.failure(error))
                }
            }
        }
    }

    private final class SnapshotSession: NSObject, LibboxTailscaleStatusHandlerProtocol, @unchecked Sendable {
        private let access = NSLock()
        private var continuation: CheckedContinuation<TaildropTargetList, Error>?
        private var subscription: LibboxTailscaleStatusSubscription?
        private var finished = false

        func expect(_ newContinuation: CheckedContinuation<TaildropTargetList, Error>) {
            access.lock()
            defer { access.unlock() }
            continuation = newContinuation
        }

        func attach(_ newSubscription: LibboxTailscaleStatusSubscription) {
            access.lock()
            if finished {
                access.unlock()
                try? newSubscription.close()
                return
            }
            subscription = newSubscription
            access.unlock()
        }

        func finish(_ result: Result<TaildropTargetList, Error>) {
            access.lock()
            guard let pending = continuation else {
                access.unlock()
                return
            }
            continuation = nil
            finished = true
            access.unlock()
            pending.resume(with: result)
        }

        func close() {
            access.lock()
            let current = subscription
            subscription = nil
            finished = true
            access.unlock()
            try? current?.close()
        }

        func onStatusUpdate(_ status: LibboxTailscaleStatusUpdate?) {
            guard let status else { return }
            finish(.success(Self.convert(status)))
        }

        func onError(_ message: String?) {
            var text = message ?? ""
            if text.isEmpty {
                text = "tailscale status stream closed"
            }
            finish(.failure(NSError(domain: "TaildropTargets", code: 0, userInfo: [
                NSLocalizedDescriptionKey: text,
            ])))
        }

        private static func convert(_ status: LibboxTailscaleStatusUpdate) -> TaildropTargetList {
            var endpoints: [TaildropTargetEndpoint] = []
            var hasRunningEndpoint = false
            var hasSharingEndpoint = false
            guard let endpointIterator = status.endpoints() else {
                return TaildropTargetList(endpoints: [], hasRunningEndpoint: false, hasSharingEndpoint: false)
            }
            while endpointIterator.hasNext() {
                guard let endpoint = endpointIterator.next() else { continue }
                guard endpoint.backendState == "Running" else { continue }
                hasRunningEndpoint = true
                guard endpoint.canShareFiles else { continue }
                hasSharingEndpoint = true
                let selfStableID = endpoint.self_?.stableID
                var peers: [TaildropTargetPeer] = []
                if let groupIterator = endpoint.userGroups() {
                    while groupIterator.hasNext() {
                        guard let group = groupIterator.next(), let peerIterator = group.peers() else { continue }
                        while peerIterator.hasNext() {
                            guard let peer = peerIterator.next() else { continue }
                            guard peer.online, peer.canReceiveFiles, peer.stableID != selfStableID else { continue }
                            peers.append(TaildropTargetPeer(
                                stableID: peer.stableID,
                                name: displayName(peer),
                                os: peer.os
                            ))
                        }
                    }
                }
                guard !peers.isEmpty else { continue }
                endpoints.append(TaildropTargetEndpoint(
                    endpointTag: endpoint.endpointTag,
                    networkName: endpoint.networkName,
                    peers: peers
                ))
            }
            return TaildropTargetList(
                endpoints: endpoints,
                hasRunningEndpoint: hasRunningEndpoint,
                hasSharingEndpoint: hasSharingEndpoint
            )
        }

        private static func displayName(_ peer: LibboxTailscalePeer) -> String {
            let segment = peer.dnsName.split(separator: ".").first.map(String.init) ?? ""
            return segment.isEmpty ? peer.hostName : segment
        }
    }
}
