import Library
import SwiftUI

@MainActor
public struct OpenConnectEndpointView: View {
    @ObservedObject var viewModel: OpenConnectStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthURLQRCode = false
    let endpointTag: String

    public init(viewModel: OpenConnectStatusViewModel, endpointTag: String) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
    }

    private var endpoint: OpenConnectEndpointData? {
        viewModel.endpoint(tag: endpointTag)
    }

    private var authForm: OpenConnectAuthFormData? {
        guard let endpoint, endpoint.state == "auth-pending" else {
            return nil
        }
        return endpoint.authForm
    }

    private var navigationTitleKey: LocalizedStringKey {
        viewModel.endpoints.count > 1 ? "OpenConnect: \(endpointTag)" : "OpenConnect"
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
                        if !tunnelInfo.flavor.isEmpty {
                            FormTextItem("Flavor", tunnelInfo.flavor)
                        }
                        if !tunnelInfo.transport.isEmpty {
                            FormTextItem("Transport", tunnelInfo.transport)
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
                if let authForm {
                    Section("Authentication") {
                        if !authForm.url.isEmpty {
                            if let url = URL(string: authForm.url) {
                                #if !os(tvOS)
                                    Link("Open Auth URL", destination: url)
                                #endif
                                Button("Open Auth URL as QR Code") {
                                    showAuthURLQRCode = true
                                }
                            }
                        } else {
                            OpenConnectAuthFormContent(viewModel: viewModel, endpointTag: endpointTag, form: authForm)
                                .id(authForm.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitleKey)
        .alert($viewModel.alert)
        .sheet(isPresented: $showAuthURLQRCode) {
            if let authForm {
                URLQRCodeSheet(url: authForm.url, title: String(localized: "Auth URL"))
            }
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
private struct OpenConnectAuthFormContent: View {
    @ObservedObject var viewModel: OpenConnectStatusViewModel
    let endpointTag: String
    let form: OpenConnectAuthFormData

    @State private var values: [String: String]
    @State private var submitting = false
    @State private var submitted = false

    init(viewModel: OpenConnectStatusViewModel, endpointTag: String, form: OpenConnectAuthFormData) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
        self.form = form
        _values = State(initialValue: Dictionary(
            form.fields.map { ($0.submissionKey, Self.initialFieldValue($0)) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    var body: some View {
        Group {
            if submitted {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Verifying")
                }
            } else {
                if !form.banner.isEmpty {
                    Text(form.banner)
                        .foregroundStyle(.secondary)
                }
                if !form.message.isEmpty {
                    Text(form.message)
                }
                ForEach(form.fields) { field in
                    fieldView(field)
                }
                FormButton {
                    submit()
                } label: {
                    if submitting {
                        ProgressView()
                    } else {
                        Text(form.fields.isEmpty ? "Continue" : "Submit")
                    }
                }
                .disabled(submitting)
            }
        }
        .onAppear {
            if !form.error.isEmpty {
                viewModel.alert = AlertState(errorMessage: form.error)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: OpenConnectAuthFormFieldData) -> some View {
        let label = field.label.isEmpty ? field.name : field.label
        switch field.kind {
        case "select":
            Picker(label, selection: binding(for: field)) {
                ForEach(field.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .disabled(submitting)
        case "password":
            FormItem(label) {
                SecureField(label, text: binding(for: field))
                    .multilineTextAlignment(.trailing)
                    .disabled(submitting)
            }
        default:
            FormItem(label) {
                TextField(label, text: binding(for: field))
                    .multilineTextAlignment(.trailing)
                    .disabled(submitting)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #endif
            }
        }
    }

    private func binding(for field: OpenConnectAuthFormFieldData) -> Binding<String> {
        Binding(
            get: { values[field.submissionKey] ?? "" },
            set: { values[field.submissionKey] = $0 }
        )
    }

    private func submit() {
        submitting = true
        Task {
            let message = await viewModel.submitAuthForm(endpointTag: endpointTag, formID: form.id, values: values)
            submitting = false
            if let message {
                viewModel.alert = AlertState(errorMessage: message)
            } else {
                submitted = true
            }
        }
    }

    private static func initialFieldValue(_ field: OpenConnectAuthFormFieldData) -> String {
        if field.kind != "select" {
            return field.value
        }
        if field.options.contains(where: { $0.value == field.value }) {
            return field.value
        }
        return field.options.first?.value ?? ""
    }
}
