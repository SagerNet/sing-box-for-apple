import Library
import SwiftUI

private enum ProbeState: Equatable {
    case idle, checking, available, unavailable
}

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

    @State private var probeState: ProbeState = .idle
    @State private var probeTask: Task<Void, Never>?

    public init(_ server: RemoteServer?, onChanged: @escaping () async -> Void) {
        origin = server
        self.onChanged = onChanged
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: RemoteServer.normalizeURL(server?.url ?? ""))
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
            Section {
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
            } header: {
                Text("Server")
            } footer: {
                if probeState != .idle {
                    reachabilityFooter
                }
            }
            #if os(tvOS)
                Section {
                    FormButton {
                        Task {
                            await save()
                        }
                    } label: {
                        Label("Save", systemImage: "doc.fill")
                    }
                }
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
        .onChangeCompat(of: url) { scheduleProbe() }
        .onChangeCompat(of: secret) { scheduleProbe() }
        .task { scheduleProbe(immediate: true) }
    }

    private var reachabilityFooter: some View {
        HStack(spacing: 8) {
            switch probeState {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .foregroundStyle(.secondary)
            case .available:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Available")
                    .foregroundStyle(.green)
            case .unavailable:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Unavailable")
                    .foregroundStyle(.red)
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleProbe(immediate: Bool = false) {
        probeTask?.cancel()
        guard (try? RemoteServer.validateURL(url)) != nil else {
            probeState = .idle
            return
        }
        let probeURL = url
        let probeSecret = secret
        probeState = .checking
        probeTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled {
                    return
                }
            }
            let reachable = await probeReachable(url: probeURL, secret: probeSecret)
            if Task.isCancelled {
                return
            }
            probeState = reachable ? .available : .unavailable
        }
    }

    private func probeReachable(url: String, secret: String) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        continuation.resume(returning: CommandTarget.probe(url: url, secret: secret))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return false
            }
            let reachable = await group.next() ?? false
            group.cancelAll()
            return reachable
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
            #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await save()
                            }
                        }
                    }
                }
            #endif
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
