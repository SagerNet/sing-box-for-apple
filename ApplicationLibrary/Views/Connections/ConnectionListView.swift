import Library
import SwiftUI

@MainActor
public struct ConnectionListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = ConnectionListViewModel()

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.isLoading {
                Text("Loading...")
            } else {
                if viewModel.connections.isEmpty {
                    Text("Empty connections")
                } else {
                    ScrollView {
                        VStack {
                            ForEach(viewModel.filteredConnections(), id: \.id) { it in
                                ConnectionView(it)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        #if !os(tvOS)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("State", selection: $viewModel.connectionStateFilter) {
                        ForEach(ConnectionStateFilter.allCases) { state in
                            Text(state.name)
                        }
                    }

                    Picker("Sort By", selection: $viewModel.connectionSort) {
                        ForEach(ConnectionSort.allCases, id: \.self) { sortBy in
                            Text(sortBy.name)
                        }
                    }

                    Button("Close All Connections", role: .destructive) {
                        viewModel.closeAllConnections()
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.circle")
                }
                if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                } else {
                    StartStopButton()
                }
            }
        }
        #endif
        #if os(macOS)
        .searchable(text: $viewModel.searchText)
        #endif
        .alert($viewModel.alert)
        .onAppear {
            viewModel.connect()
        }
        .onReceive(environments.commandClient.$connections) { connections in
            viewModel.setConnections(connections)
        }
        .onChangeCompat(of: viewModel.connectionStateFilter) { filter in
            environments.commandClient.connectionStateFilter = filter
            environments.commandClient.filterConnectionsNow()
        }
        .onChangeCompat(of: viewModel.connectionSort) { sort in
            environments.commandClient.connectionSort = sort
            environments.commandClient.filterConnectionsNow()
        }
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
}
