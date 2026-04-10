import Foundation
import Libbox
import Library
import SwiftUI

public struct TailscalePeerData: Identifiable {
    public let id: String
    public let hostName: String
    public let dnsName: String
    public let os: String
    public let tailscaleIPs: [String]
    public let online: Bool
    public let exitNode: Bool
    public let exitNodeOption: Bool
    public let active: Bool
    public let rxBytes: Int64
    public let txBytes: Int64
    public let keyExpiry: Int64
}

public struct TailscaleUserGroupData: Identifiable {
    public let id: Int64
    public let loginName: String
    public let displayName: String
    public let profilePicURL: String
    public let peers: [TailscalePeerData]
}

public struct TailscaleEndpointData: Identifiable {
    public let id: String
    public let endpointTag: String
    public let backendState: String
    public let authURL: String
    public let networkName: String
    public let magicDNSSuffix: String
    public let selfPeer: TailscalePeerData?
    public let userGroups: [TailscaleUserGroupData]
}

@MainActor
public final class TailscaleStatusViewModel: BaseViewModel {
    @Published public var endpoints: [TailscaleEndpointData] = []
    @Published public var isSubscribed = false

    private var runningTask: Task<Void, Never>?

    public func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true

        let handler = StatusHandler(self)
        runningTask = Task { [weak self] in
            do {
                try await Task.detached {
                    try LibboxNewStandaloneCommandClient()!.subscribeTailscaleStatus(handler)
                }.value
            } catch {
                guard let self else { return }
                self.isSubscribed = false
                self.endpoints = []
            }
            self?.runningTask = nil
        }
    }

    public func cancel() {
        runningTask?.cancel()
        runningTask = nil
        isSubscribed = false
        endpoints = []
    }

    public func endpoint(tag: String) -> TailscaleEndpointData? {
        endpoints.first { $0.endpointTag == tag }
    }

    private final class StatusHandler: NSObject, LibboxTailscaleStatusHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: TailscaleStatusViewModel?

        init(_ viewModel: TailscaleStatusViewModel?) {
            self.viewModel = viewModel
        }

        func onStatusUpdate(_ status: LibboxTailscaleStatusUpdate?) {
            guard let status else { return }
            let endpoints = Self.convertUpdate(status)
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isSubscribed else { return }
                viewModel.endpoints = endpoints
            }
        }

        func onError(_ message: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isSubscribed else { return }
                viewModel.isSubscribed = false
                viewModel.endpoints = []
                if let message {
                    viewModel.alert = AlertState(errorMessage: message)
                }
            }
        }

        private static func convertUpdate(_ status: LibboxTailscaleStatusUpdate) -> [TailscaleEndpointData] {
            var endpoints: [TailscaleEndpointData] = []
            if let iterator = status.endpoints() {
                while iterator.hasNext() {
                    if let endpoint = iterator.next() {
                        endpoints.append(convertEndpoint(endpoint))
                    }
                }
            }
            return endpoints
        }

        private static func convertEndpoint(_ endpoint: LibboxTailscaleEndpointStatus) -> TailscaleEndpointData {
            var userGroups: [TailscaleUserGroupData] = []
            if let groupIterator = endpoint.userGroups() {
                while groupIterator.hasNext() {
                    if let group = groupIterator.next() {
                        userGroups.append(convertUserGroup(group))
                    }
                }
            }
            return TailscaleEndpointData(
                id: endpoint.endpointTag,
                endpointTag: endpoint.endpointTag,
                backendState: endpoint.backendState,
                authURL: endpoint.authURL,
                networkName: endpoint.networkName,
                magicDNSSuffix: endpoint.magicDNSSuffix,
                selfPeer: endpoint.self_ != nil ? convertPeer(endpoint.self_!) : nil,
                userGroups: userGroups
            )
        }

        private static func convertUserGroup(_ group: LibboxTailscaleUserGroup) -> TailscaleUserGroupData {
            var peers: [TailscalePeerData] = []
            if let peerIterator = group.peers() {
                while peerIterator.hasNext() {
                    if let peer = peerIterator.next() {
                        peers.append(convertPeer(peer))
                    }
                }
            }
            return TailscaleUserGroupData(
                id: group.userID,
                loginName: group.loginName,
                displayName: group.displayName,
                profilePicURL: group.profilePicURL,
                peers: peers
            )
        }

        private static func convertPeer(_ peer: LibboxTailscalePeer) -> TailscalePeerData {
            var ips: [String] = []
            if let ipIterator = peer.tailscaleIPs() {
                while ipIterator.hasNext() {
                    ips.append(ipIterator.next())
                }
            }
            return TailscalePeerData(
                id: peer.dnsName.isEmpty ? peer.hostName : peer.dnsName,
                hostName: peer.hostName,
                dnsName: peer.dnsName,
                os: peer.os,
                tailscaleIPs: ips,
                online: peer.online,
                exitNode: peer.exitNode,
                exitNodeOption: peer.exitNodeOption,
                active: peer.active,
                rxBytes: peer.rxBytes,
                txBytes: peer.txBytes,
                keyExpiry: peer.keyExpiry
            )
        }
    }
}
