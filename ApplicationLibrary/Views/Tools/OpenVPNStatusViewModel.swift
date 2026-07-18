import Foundation
import Libbox
import Library
import SwiftUI

public struct OpenVPNChallengeData {
    public let id: String
    public let kind: String
    public let username: String
    public let message: String
    public let url: String
    public let secretMessage: String
    public let echo: Bool
    public let previousError: String
    public let deadline: Int64
}

public struct OpenVPNTunnelInfoData {
    public let server: String
    public let network: String
    public let cipher: String
    public let ipv4: [String]
    public let ipv6: [String]
    public let dns: [String]
    public let mtu: Int32
    public let connectedSince: Int64
}

public struct OpenVPNEndpointData: Identifiable {
    public var id: String {
        endpointTag
    }

    public let endpointTag: String
    public let state: String
    public let stateText: String
    public let challenge: OpenVPNChallengeData?
    public let error: String
    public let tunnelInfo: OpenVPNTunnelInfoData?
}

@MainActor
public final class OpenVPNStatusViewModel: BaseViewModel {
    @Published public var endpoints: [OpenVPNEndpointData] = []
    @Published public var isSubscribed = false

    private static let minAPIVersionOpenVPN: Int32 = 3

    private var statusSubscription: LibboxOpenVPNStatusSubscription?

    public func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true

        let handler = StatusHandler(self)
        Task { [weak self] in
            do {
                let subscription = try await Task.detached { () -> LibboxOpenVPNStatusSubscription? in
                    let client = try CommandTarget.standaloneClient()
                    var apiVersion: Int32 = 0
                    try client.getAPIVersion(&apiVersion)
                    guard apiVersion >= Self.minAPIVersionOpenVPN else { return nil }
                    return try client.subscribeOpenVPNStatus(handler)
                }.value
                guard let self else { return }
                guard let subscription else {
                    self.isSubscribed = false
                    self.endpoints = []
                    return
                }
                self.statusSubscription = subscription
            } catch {
                guard let self else { return }
                self.isSubscribed = false
                self.endpoints = []
            }
        }
    }

    public func cancel() {
        try? statusSubscription?.close()
        statusSubscription = nil
        isSubscribed = false
        endpoints = []
    }

    public func endpoint(tag: String) -> OpenVPNEndpointData? {
        endpoints.first { $0.endpointTag == tag }
    }

    public func submitChallengeResponse(
        endpointTag: String,
        challengeID: String,
        username: String,
        password: String,
        secret: String
    ) async -> String? {
        do {
            try await Task.detached {
                let response = LibboxOpenVPNChallengeResponse()
                response.username = username
                response.password = password
                response.secret = secret
                try CommandTarget.standaloneClient().submitOpenVPNChallengeResponse(endpointTag, challengeID: challengeID, response: response)
            }.value
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private final class StatusHandler: NSObject, LibboxOpenVPNStatusHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: OpenVPNStatusViewModel?

        init(_ viewModel: OpenVPNStatusViewModel?) {
            self.viewModel = viewModel
        }

        func onStatusUpdate(_ status: LibboxOpenVPNStatusUpdate?) {
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
                viewModel.statusSubscription = nil
                viewModel.endpoints = []
                if let message {
                    viewModel.alert = AlertState(errorMessage: message)
                }
            }
        }

        private static func convertUpdate(_ status: LibboxOpenVPNStatusUpdate) -> [OpenVPNEndpointData] {
            var endpoints: [OpenVPNEndpointData] = []
            if let iterator = status.endpoints() {
                while iterator.hasNext() {
                    if let endpoint = iterator.next() {
                        endpoints.append(convertEndpoint(endpoint))
                    }
                }
            }
            return endpoints
        }

        private static func convertEndpoint(_ endpoint: LibboxOpenVPNEndpointStatus) -> OpenVPNEndpointData {
            OpenVPNEndpointData(
                endpointTag: endpoint.endpointTag,
                state: endpoint.state,
                stateText: endpoint.stateText,
                challenge: endpoint.challenge.map(convertChallenge),
                error: endpoint.error,
                tunnelInfo: endpoint.tunnelInfo.map(convertTunnelInfo)
            )
        }

        private static func convertChallenge(_ challenge: LibboxOpenVPNChallenge) -> OpenVPNChallengeData {
            OpenVPNChallengeData(
                id: challenge.id_,
                kind: challenge.kind,
                username: challenge.username,
                message: challenge.message,
                url: challenge.url,
                secretMessage: challenge.secretMessage,
                echo: challenge.echo,
                previousError: challenge.previousError,
                deadline: challenge.deadline
            )
        }

        private static func convertTunnelInfo(_ info: LibboxOpenVPNTunnelInfo) -> OpenVPNTunnelInfoData {
            OpenVPNTunnelInfoData(
                server: info.server,
                network: info.network,
                cipher: info.cipher,
                ipv4: info.iPv4()?.toArray() ?? [],
                ipv6: info.iPv6()?.toArray() ?? [],
                dns: info.dns()?.toArray() ?? [],
                mtu: info.mtu,
                connectedSince: info.connectedSince
            )
        }
    }
}
