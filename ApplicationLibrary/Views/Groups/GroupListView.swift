import Library
import SwiftUI

public struct GroupListView: View {
    @Environment(\.scenePhase) private var scenePhase
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
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                viewModel.connect()
            } else {
                viewModel.disconnect()
            }
        }
    }
}
