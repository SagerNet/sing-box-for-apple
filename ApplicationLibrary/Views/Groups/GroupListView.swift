import Library
import SwiftUI

public struct GroupListView: View {
    @EnvironmentObject private var commandClient: CommandClient
    @StateObject private var viewModel = GroupListViewModel()

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.isLoading {
                Text("Loading...")
            } else if !viewModel.groups.isEmpty {
                ScrollView {
                    VStack {
                        ForEach(viewModel.groups, id: \.hashValue) { it in
                            GroupView(it)
                        }
                    }.padding()
                }
            } else {
                Text("Empty groups")
            }
        }
        .onAppear {
            viewModel.setCommandClient(commandClient)
            viewModel.connect()
        }
    }
}
