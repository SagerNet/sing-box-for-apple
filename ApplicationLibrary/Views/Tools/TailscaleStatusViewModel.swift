import Foundation
import Libbox
import Library
import SwiftUI

public struct TailscalePeerData: Identifiable {
    public let id: String
    public let stableID: String
    public let hostName: String
    public let dnsName: String
    public let os: String
    public let tailscaleIPs: [String]
    public let sshHostKeys: [String]
    public let online: Bool
    public let exitNode: Bool
    public let exitNodeOption: Bool
    public let shareeNode: Bool
    public let expired: Bool
    public let active: Bool
    public let rxBytes: Int64
    public let txBytes: Int64
    public let keyExpiry: Int64
    public let lastSeen: Int64
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
    public let exitNode: TailscalePeerData?
    public let userGroups: [TailscaleUserGroupData]

    public var hasExitNodeCandidates: Bool {
        if exitNode != nil { return true }
        let selfStableID = selfPeer?.stableID
        return userGroups.contains { group in
            group.peers.contains { $0.exitNodeOption && $0.stableID != selfStableID }
        }
    }
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
        TailscaleSSHLaunchService.shared.sshPeers = []
        TailscaleSSHLaunchService.shared.quickConnectPeerIDs = []
    }

    public func endpoint(tag: String) -> TailscaleEndpointData? {
        endpoints.first { $0.endpointTag == tag }
    }

    public func setExitNode(endpointTag: String, stableID: String) async {
        do {
            try await Task.detached {
                try LibboxNewStandaloneCommandClient()!.setTailscaleExitNode(endpointTag, stableID: stableID)
            }.value
        } catch {
            alert = AlertState(action: "set exit node", error: error)
        }
    }

    fileprivate func updateSSHPeersOnService(_ endpoints: [TailscaleEndpointData]) {
        var allSSHPeers: [TailscaleSSHPeerEntry] = []
        for endpoint in endpoints {
            for group in endpoint.userGroups {
                for peer in group.peers where peer.online && !peer.sshHostKeys.isEmpty && !peer.tailscaleIPs.isEmpty {
                    allSSHPeers.append(TailscaleSSHPeerEntry(
                        endpointTag: endpoint.endpointTag,
                        hostName: peer.hostName,
                        peerAddress: peer.tailscaleIPs.first!,
                        stableID: peer.stableID,
                        sshHostKeys: peer.sshHostKeys
                    ))
                }
            }
        }
        TailscaleSSHLaunchService.shared.sshPeers = allSSHPeers
        Task {
            let qcSet = await SharedPreferences.tailscaleSSHQuickConnectPeers.get()
            TailscaleSSHLaunchService.shared.quickConnectPeerIDs = qcSet
        }
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
                viewModel.updateSSHPeersOnService(endpoints)
            }
        }

        func onError(_ message: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isSubscribed else { return }
                viewModel.isSubscribed = false
                viewModel.endpoints = []
                TailscaleSSHLaunchService.shared.sshPeers = []
                TailscaleSSHLaunchService.shared.quickConnectPeerIDs = []
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
                exitNode: endpoint.exitNode != nil ? convertPeer(endpoint.exitNode!) : nil,
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
            var sshKeys: [String] = []
            if let keyIterator = peer.sshHostKeys() {
                while keyIterator.hasNext() {
                    sshKeys.append(keyIterator.next())
                }
            }
            return TailscalePeerData(
                id: peer.dnsName.isEmpty ? peer.hostName : peer.dnsName,
                stableID: peer.stableID,
                hostName: peer.hostName,
                dnsName: peer.dnsName,
                os: peer.os,
                tailscaleIPs: ips,
                sshHostKeys: sshKeys,
                online: peer.online,
                exitNode: peer.exitNode,
                exitNodeOption: peer.exitNodeOption,
                shareeNode: peer.shareeNode,
                expired: peer.expired,
                active: peer.active,
                rxBytes: peer.rxBytes,
                txBytes: peer.txBytes,
                keyExpiry: peer.keyExpiry,
                lastSeen: peer.lastSeen
            )
        }
    }
}
