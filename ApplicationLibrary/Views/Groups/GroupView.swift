import Library
import SwiftUI

@MainActor
public struct GroupView: View {
    @EnvironmentObject private var listViewModel: GroupListViewModel
    @Binding private var group: OutboundGroup
    @State private var geometryWidth: CGFloat = 300

    public init(_ group: Binding<OutboundGroup>) {
        _group = group
    }

    private var title: some View {
        HStack {
            Text(group.tag)
                .font(.headline)
            Text(group.displayType)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\(group.items.count)")
                .font(.subheadline)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .background(Color.gray.opacity(0.5))
                .cornerRadius(4)
            Button {
                listViewModel.toggleExpand(groupTag: group.tag)
            } label: {
                if group.isExpand {
                    Image(systemName: "arrow.down.to.line")
                } else {
                    Image(systemName: "arrow.up.to.line")
                }
            }
            #if os(macOS) || os(tvOS)
            .buttonStyle(.plain)
            #endif
            Button {
                listViewModel.performURLTest(group.tag)
            } label: {
                Image(systemName: "bolt.fill")
            }
            #if os(macOS) || os(tvOS)
            .buttonStyle(.plain)
            #endif
        }
        .padding([.top, .bottom], 8)
        .animation(.easeInOut, value: group.isExpand)
    }

    public var body: some View {
        Section {
            if group.isExpand {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()),
                                         count: explandColumnCount()))
                {
                    ForEach(group.items, id: \.tag) { it in
                        GroupItemView($group, it)
                    }
                }
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(itemGroups.enumerated()), id: \.offset) { items in
                        HStack(spacing: 5) {
                            ForEach(items.element, id: \.tag) { it in
                                ZStack {
                                    Rectangle()
                                        .fill(it.delayColor)
                                    if it.tag == group.selected {
                                        Rectangle()
                                            .fill(Color.white)
                                        #if !os(tvOS)
                                            .frame(width: 5, height: 5)
                                        #else
                                            .frame(width: 15, height: 15)
                                        #endif
                                    }
                                }
                                #if !os(tvOS)
                                .frame(width: 10, height: 10)
                                #else
                                .frame(width: 30, height: 30)
                                #endif
                            }
                        }.frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        } header: {
            title
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background {
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .frame(height: 1)
                    .onChangeCompat(of: geometry.size.width) { newValue in
                        geometryWidth = newValue
                    }
                    .onAppear {
                        geometryWidth = geometry.size.width
                    }
            }.padding()
        }
    }

    private var itemGroups: [[OutboundGroupItem]] {
        let count: Int
        #if os(tvOS)
            count = Int(Int(geometryWidth) / 40)
        #else
            count = Int(Int(geometryWidth) / 20)
        #endif
        if count == 0 {
            return [group.items]
        } else {
            return group.items.chunked(
                into: count
            )
        }
    }

    private func explandColumnCount() -> Int {
        let standardCount = Int(Int(geometryWidth) / 180)
        #if os(iOS)
            return standardCount < 2 ? 2 : standardCount
        #elseif os(tvOS)
            return 4
        #else
            return standardCount < 1 ? 1 : standardCount
        #endif
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
