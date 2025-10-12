import Combine
import Libbox
import Library
import SwiftUI

@MainActor
public class ConnectionListViewModel: ObservableObject {
    @Published public var isLoading = true
    @Published public var connections: [Connection] = []
    @Published public var searchText = ""
    @Published public var alert: Alert?
    @Published public var connectionStateFilter: ConnectionStateFilter {
        didSet {
            commandClient?.connectionStateFilter = connectionStateFilter
            commandClient?.filterConnectionsNow()
            saveStateFilterTask?.cancel()
            saveStateFilterTask = Task {
                await SharedPreferences.connectionStateFilter.set(connectionStateFilter.rawValue)
            }
        }
    }

    @Published public var connectionSort: ConnectionSort {
        didSet {
            commandClient?.connectionSort = connectionSort
            commandClient?.filterConnectionsNow()
            saveSortTask?.cancel()
            saveSortTask = Task {
                await SharedPreferences.connectionSort.set(connectionSort.rawValue)
            }
        }
    }

    private var commandClient: CommandClient?
    private var cancellables = Set<AnyCancellable>()
    private var connectTask: Task<Void, Never>?
    private var saveStateFilterTask: Task<Void, Never>?
    private var saveSortTask: Task<Void, Never>?

    public init() {
        connectionStateFilter = .active
        connectionSort = .byDate
    }

    public func setCommandClient(_ client: CommandClient) {
        commandClient = client
        client.$connections
            .compactMap { $0 }
            .sink { [weak self] goConnections in
                self?.setConnections(goConnections)
            }
            .store(in: &cancellables)
    }

    public func connect() {
        if ApplicationLibrary.inPreview {
            isLoading = false
            return
        }

        connectTask?.cancel()
        connectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadPreferences()
            if Task.isCancelled { return }
            self.connectTask = nil
        }
    }

    private func loadPreferences() async {
        let filter = await ConnectionStateFilter(rawValue: SharedPreferences.connectionStateFilter.get()) ?? .active
        let sort = await ConnectionSort(rawValue: SharedPreferences.connectionSort.get()) ?? .byDate
        connectionStateFilter = filter
        connectionSort = sort
    }

    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        saveStateFilterTask?.cancel()
        saveStateFilterTask = nil
        saveSortTask?.cancel()
        saveSortTask = nil
    }

    public func closeAllConnections() {
        do {
            try LibboxNewStandaloneCommandClient()!.closeConnections()
        } catch {
            alert = Alert(error)
        }
    }

    public func filteredConnections() -> [Connection] {
        connections.filter { connection in
            searchText == "" || connection.performSearch(searchText)
        }
    }

    private func setConnections(_ goConnections: [LibboxConnection]) {
        connections = convertConnections(goConnections)
        isLoading = false
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
