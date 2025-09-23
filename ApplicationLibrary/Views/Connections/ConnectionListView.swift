import Libbox
import Library
import SwiftUI

@MainActor
public struct ConnectionListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = true
    @StateObject private var commandClient = CommandClient(.connections)
    @State private var connections: [Connection] = []
    @State private var searchText = ""
    @State private var alert: Alert?

    public init() {}
    public var body: some View {
        VStack {
            if isLoading {
                Text("Loading...")
            } else {
                if connections.isEmpty {
                    Text("Empty connections")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading) {
                            ForEach(connections.filter { it in
                                searchText == "" || it.performSearch(searchText)
                            }, id: \.hashValue) { it in
                                ConnectionView(it)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        #if !os(tvOS)
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("State", selection: $commandClient.connectionStateFilter) {
                        ForEach(ConnectionStateFilter.allCases) { state in
                            Text(state.name)
                        }
                    }

                    Picker("Sort By", selection: $commandClient.connectionSort) {
                        ForEach(ConnectionSort.allCases, id: \.self) { sortBy in
                            Text(sortBy.name)
                        }
                    }

                    Button("Close All Connections", role: .destructive) {
                        do {
                            try LibboxNewStandaloneCommandClient()!.closeConnections()
                        } catch {
                            alert = Alert(error)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.circle")
                }
            }
        }
        #endif
        #if os(macOS)
        .searchable(text: $searchText)
        #endif
        .alertBinding($alert)
        .onAppear {
            connect()
        }
        .onDisappear {
            commandClient.disconnect()
        }
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                commandClient.connect()
            } else {
                commandClient.disconnect()
            }
        }
        .onChangeCompat(of: commandClient.connectionStateFilter) { it in
            commandClient.filterConnectionsNow()
            Task {
                await SharedPreferences.connectionStateFilter.set(it.rawValue)
            }
        }
        .onChangeCompat(of: commandClient.connectionSort) { it in
            commandClient.filterConnectionsNow()
            Task {
                await SharedPreferences.connectionSort.set(it.rawValue)
            }
        }
        .onReceive(commandClient.$connections, perform: { connections in
            if let connections {
                self.connections = convertConnections(connections)
                isLoading = false
            }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        #if os(iOS)
            .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    private var backgroundColor: Color {
        #if os(iOS)
            return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
            return Color(nsColor: .textBackgroundColor)
        #elseif os(tvOS)
            return Color(uiColor: .black)
        #endif
    }

    private func connect() {
        if ApplicationLibrary.inPreview {
            isLoading = false
        } else {
            commandClient.connect()
        }
    }

    private func convertConnections(_ goConnections: [LibboxConnection]) -> [Connection] {
        var connections = [Connection]()
        for goConnection in goConnections {
            if goConnection.outboundType == "dns" {
                continue
            }
            var closedAt: Date?
            if goConnection.closedAt > 0 {
                closedAt = Date(timeIntervalSince1970: Double(goConnection.closedAt) / 1000)
            }
            connections.append(Connection(
                id: goConnection.id_,
                inbound: goConnection.inbound,
                inboundType: goConnection.inboundType,
                ipVersion: goConnection.ipVersion,
                network: goConnection.network,
                source: goConnection.source,
                destination: goConnection.destination,
                domain: goConnection.domain,
                displayDestination: goConnection.displayDestination(),
                protocolName: goConnection.protocol,
                user: goConnection.user,
                fromOutbound: goConnection.fromOutbound,
                createdAt: Date(timeIntervalSince1970: Double(goConnection.createdAt) / 1000),
                closedAt: closedAt,
                upload: goConnection.uplink,
                download: goConnection.downlink,
                uploadTotal: goConnection.uplinkTotal,
                downloadTotal: goConnection.downlinkTotal,
                rule: goConnection.rule,
                outbound: goConnection.outbound,
                outboundType: goConnection.outboundType,
                chain: goConnection.chain()!.toArray()
            ))
        }
        return connections
    }
}
