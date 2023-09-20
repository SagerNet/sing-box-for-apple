import Libbox
import Library
import SwiftUI

public struct GroupListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = true
    @StateObject private var commandClient = CommandClient(.groups)
    @State private var groups: [OutboundGroup] = []

    public init() {}
    public var body: some View {
        VStack {
            if isLoading {
                Text("Loading...")
            } else if !groups.isEmpty {
                ScrollView {
                    VStack {
                        ForEach(groups, id: \.hashValue) { it in
                            GroupView(it)
                        }
                    }.padding()
                }
            } else {
                Text("Empty groups")
            }
        }
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
        .onReceive(commandClient.$groups, perform: { groups in
            if let groups {
                setGroups(groups)
            }
        })
    }

    private func connect() {
        if ApplicationLibrary.inPreview {
            groups = [
                OutboundGroup(tag: "my_group", type: "selector", selected: "server", selectable: true, isExpand: true, items: [
                    OutboundGroupItem(tag: "server", type: "Shadowsocks", urlTestTime: .now, urlTestDelay: 12),
                    OutboundGroupItem(tag: "server2", type: "WireGuard", urlTestTime: .now, urlTestDelay: 34),
                    OutboundGroupItem(tag: "auto", type: "URLTest", urlTestTime: .now, urlTestDelay: 100),
                ]),
                OutboundGroup(tag: "group2", type: "urltest", selected: "client", selectable: true, isExpand: false, items:
                    (0 ..< 234).map { index in
                        OutboundGroupItem(tag: "client\(index)", type: "Shadowsocks", urlTestTime: .now, urlTestDelay: UInt16(100 + index * 10))
                    }),
            ]
            isLoading = false
        } else {
            commandClient.connect()
        }
    }

    private func setGroups(_ goGroups: [LibboxOutboundGroup]) {
        var groups = [OutboundGroup]()
        for goGroup in goGroups {
            var items = [OutboundGroupItem]()
            let itemIterator = goGroup.getItems()!
            while itemIterator.hasNext() {
                let goItem = itemIterator.next()!
                items.append(OutboundGroupItem(tag: goItem.tag, type: goItem.type, urlTestTime: Date(timeIntervalSince1970: Double(goItem.urlTestTime)), urlTestDelay: UInt16(goItem.urlTestDelay)))
            }
            groups.append(OutboundGroup(tag: goGroup.tag, type: goGroup.type, selected: goGroup.selected, selectable: goGroup.selectable, isExpand: goGroup.isExpand, items: items))
        }
        self.groups = groups
        isLoading = false
    }
}
