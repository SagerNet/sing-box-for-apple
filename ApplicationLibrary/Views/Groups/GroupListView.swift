import Library
import SwiftUI

public struct GroupListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = GroupListViewModel()
    @State private var containerWidth: CGFloat = 360

    public init() {}
    public var body: some View {
        VStack {
            if viewModel.isLoading {
                Text("Loading...")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.groups, id: \.tag) { group in
                            if group.isExpand {
                                Section {
                                    GroupContentView(group: group, contentWidth: max(containerWidth - 64, 100))
                                        .padding(.bottom, 14)
                                } header: {
                                    GroupHeaderView(group: group)
                                }
                            } else {
                                GroupHeaderView(group: group)
                                GroupContentView(group: group, contentWidth: max(containerWidth - 64, 100))
                                    .padding(.bottom, 14)
                            }
                        }
                    }.padding(16)
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        containerWidth = geometry.size.width
                    }
                    .onChangeCompat(of: geometry.size.width) { newValue in
                        containerWidth = newValue
                    }
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
        .environmentObject(viewModel)
        .alert($viewModel.alert)
        .onAppear {
            viewModel.connect()
        }
        .onReceive(environments.commandClient.$groups) { groups in
            Task { @MainActor in
                viewModel.setGroups(groups)
            }
        }
    }
}
