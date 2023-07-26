import Libbox
import Library
import SwiftUI

public struct GroupView: View {
    @Binding private var expland: Bool
    @State private var group: OutboundGroup
    @State private var geometryWidth: CGFloat = 300

    public init(_ group: OutboundGroup, _ expland: Binding<Bool>) {
        self.group = group
        _expland = expland
    }

    private var title: some View {
        HStack {
            Text(group.tag)
                .font(.system(size: 17))
            Text(group.displayType)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("\(group.items.count)")
                .font(.system(size: 11))
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .background(Color.gray.opacity(0.5))
                .cornerRadius(4)
            Button {
                expland = !expland
            } label: {
                if expland {
                    Image(systemName: "arrow.down.to.line")
                } else {
                    Image(systemName: "arrow.up.to.line")
                }
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            Button {
                Task.detached {
                    doURLTest()
                }
            } label: {
                Image(systemName: "bolt.fill")
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            Spacer(minLength: 6)
        }
    }

    public var body: some View {
        Section {
            if expland {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()),
                                         count: explandColumnCount()))
                {
                    ForEach(group.items, id: \.tag) { it in
                        GroupItemView($group, it)
                    }
                }
            } else {
                VStack {
                    ForEach(Array(itemGroups.enumerated()), id: \.offset) { items in
                        HStack {
                            ForEach(items.element, id: \.tag) { it in
                                Rectangle()
                                    .fill(it.delayColor)
                                    .frame(width: 10, height: 10)
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
                    .onChange(of: geometry.size.width) { newValue in
                        geometryWidth = newValue
                    }
                    .onAppear {
                        geometryWidth = geometry.size.width
                    }
            }.padding()
        }
    }

    private var itemGroups: [[OutboundGroupItem]] {
        let count = Int(Int(geometryWidth) / 20)
        if count == 0 {
            return [group.items]
        } else {
            return group.items.chunked(
                into: count
            )
        }
    }

    private func explandColumnCount() -> Int {
        let count = Int(Int(geometryWidth) / 180)
        #if os(iOS)
            return count < 2 ? 2 : count
        #else
            return count < 1 ? 1 : count
        #endif
    }

    private func doURLTest() {
        try? LibboxNewStandaloneCommandClient(FilePath.sharedDirectory.relativePath)!.urlTest(group.tag)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
