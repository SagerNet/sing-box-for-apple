import Foundation
import Libbox
import Library
import SwiftUI

public struct OpenConnectAuthFormChoiceData: Identifiable {
    public var id: String {
        value
    }

    public let value: String
    public let label: String
}

public struct OpenConnectAuthFormFieldData: Identifiable {
    public var id: String {
        submissionKey
    }

    public let submissionKey: String
    public let name: String
    public let label: String
    public let kind: String
    public let value: String
    public let options: [OpenConnectAuthFormChoiceData]
}

public struct OpenConnectAuthFormData {
    public let fields: [OpenConnectAuthFormFieldData]
}

public struct OpenConnectBrowserRequestData {
    public let url: String
    public let finalURL: String
    public let cookieNames: [String]
    public let headerNames: [String]
}

public struct OpenConnectAuthChallengeData {
    public let id: String
    public let banner: String
    public let message: String
    public let error: String
    public let form: OpenConnectAuthFormData?
    public let browser: OpenConnectBrowserRequestData?
}

public struct OpenConnectBrowserCookieData {
    public let name: String
    public let value: String
}

public struct OpenConnectBrowserHeaderData {
    public let name: String
    public let values: [String]
}

public struct OpenConnectBrowserResultData {
    public let finalURL: String
    public let cookies: [OpenConnectBrowserCookieData]
    public let headers: [OpenConnectBrowserHeaderData]
}

public struct OpenConnectTunnelInfoData {
    public let server: String
    public let flavor: String
    public let transport: String
    public let ipv4: [String]
    public let ipv6: [String]
    public let dns: [String]
    public let mtu: Int32
    public let connectedSince: Int64
}

public struct OpenConnectEndpointData: Identifiable {
    public var id: String {
        endpointTag
    }

    public let endpointTag: String
    public let state: String
    public let stateText: String
    public let authChallenge: OpenConnectAuthChallengeData?
    public let error: String
    public let tunnelInfo: OpenConnectTunnelInfoData?
}

@MainActor
public final class OpenConnectStatusViewModel: BaseViewModel {
    @Published public var endpoints: [OpenConnectEndpointData] = []
    @Published public var isSubscribed = false

    private static let minAPIVersionOpenConnect: Int32 = 3

    private var statusSubscription: LibboxOpenConnectStatusSubscription?

    public func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true

        let handler = StatusHandler(self)
        Task { [weak self] in
            do {
                let subscription = try await Task.detached { () -> LibboxOpenConnectStatusSubscription? in
                    let client = try CommandTarget.standaloneClient()
                    var apiVersion: Int32 = 0
                    try client.getAPIVersion(&apiVersion)
                    guard apiVersion >= Self.minAPIVersionOpenConnect else { return nil }
                    return try client.subscribeOpenConnectStatus(handler)
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

    public func endpoint(tag: String) -> OpenConnectEndpointData? {
        endpoints.first { $0.endpointTag == tag }
    }

    public func submitAuthFormResponse(
        endpointTag: String,
        challengeID: String,
        values: [String: String]
    ) async -> String? {
        do {
            try await Task.detached {
                guard let formValues = LibboxNewOpenConnectFormValues() else {
                    return
                }
                for (key, value) in values {
                    formValues.add(key, value: value)
                }
                guard let response = LibboxNewOpenConnectAuthFormResponse(formValues) else {
                    return
                }
                try CommandTarget.standaloneClient().submitOpenConnectAuthResponse(
                    endpointTag,
                    challengeID: challengeID,
                    response: response
                )
            }.value
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public func submitBrowserResponse(
        endpointTag: String,
        challengeID: String,
        result: OpenConnectBrowserResultData
    ) async -> String? {
        do {
            try await Task.detached {
                guard let browserResult = LibboxNewOpenConnectBrowserResult(result.finalURL) else {
                    return
                }
                for cookie in result.cookies {
                    browserResult.addCookie(cookie.name, value: cookie.value)
                }
                for header in result.headers {
                    for value in header.values {
                        browserResult.addHeader(header.name, value: value)
                    }
                }
                guard let response = LibboxNewOpenConnectBrowserAuthResponse(browserResult) else {
                    return
                }
                try CommandTarget.standaloneClient().submitOpenConnectAuthResponse(
                    endpointTag,
                    challengeID: challengeID,
                    response: response
                )
            }.value
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private final class StatusHandler: NSObject, LibboxOpenConnectStatusHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: OpenConnectStatusViewModel?

        init(_ viewModel: OpenConnectStatusViewModel?) {
            self.viewModel = viewModel
        }

        func onStatusUpdate(_ status: LibboxOpenConnectStatusUpdate?) {
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

        private static func convertUpdate(_ status: LibboxOpenConnectStatusUpdate) -> [OpenConnectEndpointData] {
            var endpoints: [OpenConnectEndpointData] = []
            if let iterator = status.endpoints() {
                while iterator.hasNext() {
                    if let endpoint = iterator.next() {
                        endpoints.append(convertEndpoint(endpoint))
                    }
                }
            }
            return endpoints
        }

        private static func convertEndpoint(_ endpoint: LibboxOpenConnectEndpointStatus) -> OpenConnectEndpointData {
            OpenConnectEndpointData(
                endpointTag: endpoint.endpointTag,
                state: endpoint.state,
                stateText: endpoint.stateText,
                authChallenge: endpoint.authChallenge.map(convertAuthChallenge),
                error: endpoint.error,
                tunnelInfo: endpoint.tunnelInfo.map(convertTunnelInfo)
            )
        }

        private static func convertAuthChallenge(
            _ challenge: LibboxOpenConnectAuthChallenge
        ) -> OpenConnectAuthChallengeData {
            var fields: [OpenConnectAuthFormFieldData] = []
            if let fieldIterator = challenge.form?.fields() {
                while fieldIterator.hasNext() {
                    if let field = fieldIterator.next() {
                        var options: [OpenConnectAuthFormChoiceData] = []
                        if let optionIterator = field.options() {
                            while optionIterator.hasNext() {
                                if let option = optionIterator.next() {
                                    options.append(OpenConnectAuthFormChoiceData(value: option.value, label: option.label))
                                }
                            }
                        }
                        fields.append(OpenConnectAuthFormFieldData(
                            submissionKey: field.submissionKey,
                            name: field.name,
                            label: field.label,
                            kind: field.kind,
                            value: field.value,
                            options: options
                        ))
                    }
                }
            }
            let form = challenge.form.map { _ in
                OpenConnectAuthFormData(fields: fields)
            }
            let browser = challenge.browser.map {
                OpenConnectBrowserRequestData(
                    url: $0.url,
                    finalURL: $0.finalURL,
                    cookieNames: $0.cookieNames()?.toArray() ?? [],
                    headerNames: $0.headerNames()?.toArray() ?? []
                )
            }
            return OpenConnectAuthChallengeData(
                id: challenge.id_,
                banner: challenge.banner,
                message: challenge.message,
                error: challenge.error,
                form: form,
                browser: browser
            )
        }

        private static func convertTunnelInfo(_ info: LibboxOpenConnectTunnelInfo) -> OpenConnectTunnelInfoData {
            OpenConnectTunnelInfoData(
                server: info.server,
                flavor: info.flavor,
                transport: info.transport,
                ipv4: info.iPv4()?.toArray() ?? [],
                ipv6: info.iPv6()?.toArray() ?? [],
                dns: info.dns()?.toArray() ?? [],
                mtu: info.mtu,
                connectedSince: info.connectedSince
            )
        }
    }
}
