import Library
import SwiftUI

@MainActor
public struct RemoteControlView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var servers: [RemoteServer] = []
    @State private var alert: AlertState?

    #if !os(tvOS)
        @State private var editingServer: RemoteServer?
        @State private var showNewServer = false
    #endif

    public init() {}

    public var body: some View {
        content
            .alert($alert)
            .onAppear {
                Task {
                    await reload()
                }
            }
    }

    #if os(tvOS)

        private var content: some View {
            FormView {
                if !servers.isEmpty {
                    Section("Servers") {
                        ForEach(servers) { server in
                            serverRow(server)
                        }
                    }
                } else if !isLoading {
                    Section("Servers") {
                        Text("No servers")
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    FormNavigationLink {
                        EditRemoteServerView(nil) {
                            await reload()
                        }
                    } label: {
                        Label("New Server", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Remote Control")
        }

        private func serverRow(_ server: RemoteServer) -> some View {
            HStack {
                ServerActivateButton(server: server)
                    .frame(maxWidth: .infinity)
                NavigationLink {
                    EditRemoteServerView(server) {
                        await reload()
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }

    #else

        private var content: some View {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FormView {
                        serversSection
                    }
                }
            }
            .navigationTitle("Remote Control")
            .sheet(isPresented: $showNewServer) {
                serverSheet(nil)
            }
            .sheet(item: $editingServer) { server in
                serverSheet(server)
            }
        }

        private var serversSection: some View {
            Section {
                if servers.isEmpty {
                    Text("No servers")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(servers) { server in
                        serverRow(server)
                    }
                }
            } header: {
                HStack {
                    Text("Servers")
                    Spacer()
                    Button {
                        showNewServer = true
                    } label: {
                        Label("New Server", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
            }
        }

        private func serverRow(_ server: RemoteServer) -> some View {
            Button {
                editingServer = server
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.displayName)
                            .fontWeight(.medium)
                        if server.name != nil {
                            Text(server.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #elseif os(iOS)
            .foregroundStyle(.primary)
            #endif
        }

        @ViewBuilder
        private func serverSheet(_ server: RemoteServer?) -> some View {
            #if os(macOS)
                NavigationSheet {
                    EditRemoteServerView(server) {
                        await reload()
                    }
                }
                .frame(minWidth: 500, minHeight: 400)
            #else
                NavigationSheet(title: server == nil ? String(localized: "New Server") : String(localized: "Edit Server")) {
                    EditRemoteServerView(server) {
                        await reload()
                    }
                }
            #endif
        }

    #endif

    private func reload() async {
        do {
            servers = try await RemoteServerManager.list()
        } catch {
            alert = AlertState(action: "load server list", error: error)
        }
        isLoading = false
    }
}

#if os(tvOS)
    /// Owns the DismissAction instead of RemoteControlView: capturing one in a
    /// NavigationLink destination makes SwiftUI on iOS/tvOS 17 loop forever laying
    /// the pushed view out.
    @MainActor
    private struct ServerActivateButton: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @Environment(\.dismiss) private var dismiss
        @Environment(\.selection) private var selection

        let server: RemoteServer

        var body: some View {
            let isActive = environments.remoteServer?.id == server.id
            Button {
                if isActive {
                    environments.exitRemoteControl()
                } else {
                    environments.enterRemoteControl(server)
                    dismiss()
                    selection.wrappedValue = .dashboard
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.displayName)
                            .foregroundStyle(.primary)
                        if server.name != nil {
                            Text(server.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
#endif
