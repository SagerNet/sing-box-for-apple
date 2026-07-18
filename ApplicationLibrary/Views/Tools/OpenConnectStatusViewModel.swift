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
    public let id: String
    public let banner: String
    public let message: String
    public let error: String
    public let url: String
    public let fields: [OpenConnectAuthFormFieldData]
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
    public let authForm: OpenConnectAuthFormData?
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

    public func submitAuthForm(endpointTag: String, formID: String, values: [String: String]) async -> String? {
        do {
            try await Task.detached {
                guard let formValues = LibboxNewOpenConnectFormValues() else {
                    return
                }
                for (key, value) in values {
                    formValues.add(key, value: value)
                }
                try CommandTarget.standaloneClient().submitOpenConnectAuthForm(endpointTag, formID: formID, values: formValues)
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
                authForm: endpoint.authForm.map(convertAuthForm),
                error: endpoint.error,
                tunnelInfo: endpoint.tunnelInfo.map(convertTunnelInfo)
            )
        }

        private static func convertAuthForm(_ form: LibboxOpenConnectAuthForm) -> OpenConnectAuthFormData {
            var fields: [OpenConnectAuthFormFieldData] = []
            if let fieldIterator = form.fields() {
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
            return OpenConnectAuthFormData(
                id: form.id_,
                banner: form.banner,
                message: form.message,
                error: form.error,
                url: form.url,
                fields: fields
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
