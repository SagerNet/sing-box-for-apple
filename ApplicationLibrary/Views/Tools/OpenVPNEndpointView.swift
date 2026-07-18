import Library
import SwiftUI

@MainActor
public struct OpenVPNEndpointView: View {
    @ObservedObject var viewModel: OpenVPNStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthURLQRCode = false
    let endpointTag: String

    public init(viewModel: OpenVPNStatusViewModel, endpointTag: String) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
    }

    private var endpoint: OpenVPNEndpointData? {
        viewModel.endpoint(tag: endpointTag)
    }

    private var challenge: OpenVPNChallengeData? {
        guard let endpoint, endpoint.state == "auth-pending" else {
            return nil
        }
        return endpoint.challenge
    }

    private var authURL: String {
        guard let challenge, challenge.kind == "open-url" else {
            return ""
        }
        return challenge.url
    }

    private var navigationTitleKey: LocalizedStringKey {
        viewModel.endpoints.count > 1 ? "OpenVPN: \(endpointTag)" : "OpenVPN"
    }

    public var body: some View {
        FormView {
            if let endpoint {
                Section("Status") {
                    EndpointStateRow(state: endpoint.state, stateText: endpoint.stateText)
                    if endpoint.state == "connected", let tunnelInfo = endpoint.tunnelInfo {
                        if !tunnelInfo.server.isEmpty {
                            FormTextItem("Server", tunnelInfo.server)
                        }
                        if !tunnelInfo.network.isEmpty {
                            FormTextItem("Network", tunnelInfo.network)
                        }
                        if !tunnelInfo.cipher.isEmpty {
                            FormTextItem("Cipher", tunnelInfo.cipher)
                        }
                        if !tunnelInfo.ipv4.isEmpty {
                            FormTextItem("IPv4", tunnelInfo.ipv4.joined(separator: ", "))
                        }
                        if !tunnelInfo.ipv6.isEmpty {
                            FormTextItem("IPv6", tunnelInfo.ipv6.joined(separator: ", "))
                        }
                        if !tunnelInfo.dns.isEmpty {
                            FormTextItem("DNS", tunnelInfo.dns.joined(separator: ", "))
                        }
                        if tunnelInfo.mtu > 0 {
                            FormTextItem("MTU", String(tunnelInfo.mtu))
                        }
                        if tunnelInfo.connectedSince > 0 {
                            FormTextItem("Connected", relativeTime(tunnelInfo.connectedSince))
                        }
                    }
                }
                if let challenge, challenge.kind == "open-url" || challenge.kind == "credentials" || challenge.kind == "secret" {
                    Section("Authentication") {
                        if challenge.kind == "open-url" {
                            if let url = URL(string: authURL) {
                                #if !os(tvOS)
                                    Link("Open Auth URL", destination: url)
                                #endif
                                Button("Open Auth URL as QR Code") {
                                    showAuthURLQRCode = true
                                }
                            }
                        } else {
                            OpenVPNChallengeContent(viewModel: viewModel, endpointTag: endpointTag, challenge: challenge)
                                .id(challenge.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitleKey)
        .alert($viewModel.alert)
        .sheet(isPresented: $showAuthURLQRCode) {
            URLQRCodeSheet(url: authURL, title: String(localized: "Auth URL"))
        }
        .onChangeCompat(of: endpoint?.error ?? "") { error in
            if !error.isEmpty {
                viewModel.alert = AlertState(errorMessage: error)
            }
        }
        .onAppear {
            if let error = endpoint?.error, !error.isEmpty {
                viewModel.alert = AlertState(errorMessage: error)
            }
        }
        .onChangeCompat(of: endpoint == nil) { isNil in
            if isNil {
                dismiss()
            }
        }
    }

    private func relativeTime(_ timestamp: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(timestamp)), relativeTo: Date())
    }
}

private struct EndpointStateRow: View {
    let state: String
    let stateText: String

    var body: some View {
        #if os(tvOS)
            Button {} label: {
                content
            }
        #else
            content
        #endif
    }

    private var content: some View {
        HStack {
            Text("State")
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(stateColor)
                Text(stateText)
            }
        }
    }

    private var stateColor: Color {
        switch state {
        case "connected": .green
        case "auth-pending": .orange
        case "connecting": .yellow
        case "error": .red
        default: Color(.systemGray)
        }
    }
}

@MainActor
private struct OpenVPNChallengeContent: View {
    @ObservedObject var viewModel: OpenVPNStatusViewModel
    let endpointTag: String
    let challenge: OpenVPNChallengeData

    @State private var username: String
    @State private var password = ""
    @State private var secret = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(viewModel: OpenVPNStatusViewModel, endpointTag: String, challenge: OpenVPNChallengeData) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
        self.challenge = challenge
        _username = State(initialValue: challenge.username)
    }

    private var deadlineDate: Date? {
        challenge.deadline > 0 ? Date(timeIntervalSince1970: TimeInterval(challenge.deadline)) : nil
    }

    private var expired: Bool {
        if let deadlineDate {
            return deadlineDate <= now
        }
        return false
    }

    private var editable: Bool {
        !submitting && !expired
    }

    var body: some View {
        Group {
            if submitted {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Verifying")
                }
            } else {
                if !challenge.message.isEmpty {
                    Text(challenge.message)
                }
                if let deadlineDate {
                    FormTextItem("Expires", remainingTime(until: deadlineDate))
                }
                if challenge.kind == "credentials" {
                    FormItem(String(localized: "Username")) {
                        TextField("Username", text: $username)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editable)
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        #endif
                    }
                    FormItem(String(localized: "Password")) {
                        SecureField("Password", text: $password)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editable)
                    }
                    if !challenge.secretMessage.isEmpty {
                        secretField
                    }
                } else {
                    secretField
                }
                FormButton {
                    submit()
                } label: {
                    if submitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                    }
                }
                .disabled(!editable)
            }
        }
        .onAppear {
            if !challenge.previousError.isEmpty {
                viewModel.alert = AlertState(errorMessage: challenge.previousError)
            }
        }
        .onReceive(timer) { date in
            now = date
        }
    }

    @ViewBuilder
    private var secretField: some View {
        let label = challenge.secretMessage.isEmpty ? String(localized: "Response") : challenge.secretMessage
        FormItem(label) {
            if challenge.echo {
                TextField(label, text: $secret)
                    .multilineTextAlignment(.trailing)
                    .disabled(!editable)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #endif
            } else {
                SecureField(label, text: $secret)
                    .multilineTextAlignment(.trailing)
                    .disabled(!editable)
            }
        }
    }

    private func remainingTime(until deadline: Date) -> String {
        let remaining = Int(max(0, deadline.timeIntervalSince(now)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func submit() {
        submitting = true
        Task {
            let message = await viewModel.submitChallengeResponse(
                endpointTag: endpointTag,
                challengeID: challenge.id,
                username: challenge.kind == "credentials" ? username : "",
                password: challenge.kind == "credentials" ? password : "",
                secret: secret
            )
            submitting = false
            if let message {
                viewModel.alert = AlertState(errorMessage: message)
            } else {
                submitted = true
            }
        }
    }
}
