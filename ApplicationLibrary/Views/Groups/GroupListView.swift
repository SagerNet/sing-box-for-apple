import Library
import SwiftUI

public struct GroupListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = GroupListViewModel()

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.isLoading {
                Text("Loading...")
            } else if !viewModel.groups.isEmpty {
                ScrollView {
                    VStack {
                        ForEach($viewModel.groups, id: \.tag) { $group in
                            GroupView($group)
                        }
                    }.padding()
                }
            } else {
                Text("Empty groups")
            }
        }
        .environmentObject(viewModel)
        .alert($viewModel.alert)
        .onAppear {
            viewModel.connect()
        }
        .onReceive(environments.commandClient.$groups) { groups in
            viewModel.setGroups(groups)
        }
    }
}
