import Library
import SwiftUI

@MainActor
public struct EditRemoteServerView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss

    private let origin: RemoteServer?
    private let onChanged: () async -> Void

    @State private var name: String
    @State private var url: String
    @State private var secret: String

    @State private var alert: AlertState?

    public init(_ server: RemoteServer?, onChanged: @escaping () async -> Void) {
        origin = server
        self.onChanged = onChanged
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: server?.url ?? "")
        _secret = State(initialValue: server?.secret ?? "")
    }

    private var title: String {
        origin == nil ? String(localized: "New Server") : String(localized: "Edit Server")
    }

    public var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    private var formContent: some View {
        FormView {
            Section("Server") {
                FormItem(String(localized: "Name")) {
                    TextField("Name", text: $name, prompt: Text("Optional"))
                        .multilineTextAlignment(.trailing)
                }
                FormItem(String(localized: "URL")) {
                    TextField("URL", text: $url, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS) || os(tvOS)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #endif
                }
                FormItem(String(localized: "Secret")) {
                    SecureField("Secret", text: $secret, prompt: Text("Optional"))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .textContentType(.init(rawValue: ""))
                    #endif
                }
            }
            #if !os(macOS)
                Section {
                    FormButton {
                        Task {
                            await save()
                        }
                    } label: {
                        Label("Save", systemImage: "doc.fill")
                    }
                }
            #endif
            #if os(tvOS)
                if origin != nil {
                    Section {
                        FormButton(role: .destructive) {
                            Task {
                                await deleteServer()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            #endif
        }
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                formContent
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                }
            }
            .alert($alert)
        }
    #else
        private var iOSBody: some View {
            formContent
                .navigationTitle(title)
                .alert($alert)
        }
    #endif

    private func validate() -> String? {
        do {
            return try RemoteServer.validateURL(url)
        } catch {
            alert = AlertState(action: "parse server URL", error: error)
            return nil
        }
    }

    private func applyChanges(to server: RemoteServer, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        server.name = trimmedName.isEmpty ? nil : trimmedName
        server.url = url
        server.secret = secret
    }

    private func save() async {
        guard let validatedURL = validate() else {
            return
        }
        do {
            if let origin {
                applyChanges(to: origin, url: validatedURL)
                try await RemoteServerManager.update(origin)
            } else {
                let server = RemoteServer()
                applyChanges(to: server, url: validatedURL)
                try await RemoteServerManager.create(server)
            }
        } catch {
            alert = AlertState(action: "save server", error: error)
            return
        }
        await onChanged()
        dismiss()
    }

    #if os(tvOS)
        private func deleteServer() async {
            guard let origin else {
                return
            }
            do {
                if environments.remoteServer?.id == origin.id {
                    environments.exitRemoteControl()
                }
                try await RemoteServerManager.delete(origin)
            } catch {
                alert = AlertState(action: "delete server", error: error)
                return
            }
            await onChanged()
            dismiss()
        }
    #endif
}
