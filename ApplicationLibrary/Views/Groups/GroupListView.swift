import Libbox
import Library
import SwiftUI

public struct GroupListView: View {
    @State private var isLoading = true
    @State private var connectTask: Task<Void, Error>?
    @State private var commandClient: LibboxCommandClient?
    @State private var groups: [OutboundGroup] = []
    @State private var groupExpand: [String: Bool] = [:]

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear(perform: doReload)
        .onDisappear {
            connectTask?.cancel()
            if let commandClient {
                try? commandClient.disconnect()
            }
            commandClient = nil
        }
    }

    private func doReload() {
        if ApplicationLibrary.inPreview {
            groups = [
                OutboundGroup(tag: "my_group", type: "selector", selected: "server", selectable: true, isExpand: true, items: [
                    OutboundGroupItem(tag: "server", type: "Shadowsocks", urlTestTime: .now, urlTestDelay: 12),
                    OutboundGroupItem(tag: "server2", type: "WireGuard", urlTestTime: .now, urlTestDelay: 34),
                    OutboundGroupItem(tag: "auto", type: "URLTest", urlTestTime: .now, urlTestDelay: 100),
                ]),
                OutboundGroup(tag: "group2", type: "urltest", selected: "client", selectable: true, isExpand: true, items:
                    (0 ..< 234).map { index in
                        OutboundGroupItem(tag: "client\(index)", type: "Shadowsocks", urlTestTime: .now, urlTestDelay: UInt16(100 + index * 10))
                    }),
            ]
            isLoading = false
        } else {
            connectTask?.cancel()
            connectTask = Task.detached {
                await connect()
            }
        }
    }

    private func connect() async {
        let clientOptions = LibboxCommandClientOptions()
        clientOptions.command = LibboxCommandGroup
        clientOptions.statusInterval = Int64(2 * NSEC_PER_SEC)
        let client = LibboxNewCommandClient(FilePath.sharedDirectory.relativePath, groupsHandler(self), clientOptions)!

        do {
            for i in 0 ..< 10 {
                try await Task.sleep(nanoseconds: UInt64(Double(100 + (i * 50)) * Double(NSEC_PER_MSEC)))
                try Task.checkCancellation()
                let isConnected: Bool
                do {
                    try client.connect()
                    isConnected = true
                } catch {
                    isConnected = false
                }
                try Task.checkCancellation()
                if isConnected {
                    commandClient = client
                    return
                }
            }
        } catch {
            NSLog("failed to connect status: \(error.localizedDescription)")
            try? client.disconnect()
        }
    }

    private func setGroups(_ groupIterator: LibboxOutboundGroupIteratorProtocol) {
        var goGroups = [LibboxOutboundGroup]()
        while groupIterator.hasNext() {
            goGroups.append(groupIterator.next()!)
        }
        var groups = [OutboundGroup]()
        for goGroup in goGroups {
            var items = [OutboundGroupItem]()
            let itemIterator = goGroup.getItems()!
            while itemIterator.hasNext() {
                let goItem = itemIterator.next()!
                items.append(OutboundGroupItem(tag: goItem.tag, type: goItem.type, urlTestTime: Date(timeIntervalSince1970: Double(goItem.urlTestTime)), urlTestDelay: UInt16(goItem.urlTestDelay)))
            }
            groups.append(OutboundGroup(tag: goGroup.tag, type: goGroup.type, selected: goGroup.selected, selectable: goGroup.selectable, isExpand: goGroup.isExpand(), items: items))
        }
        self.groups = groups
        isLoading = false
    }

    private class groupsHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private let groupListView: GroupListView

        init(_ statusView: GroupListView) {
            groupListView = statusView
        }

        func connected() {}

        func disconnected(_: String?) {}

        func writeLog(_: String?) {}

        func writeStatus(_: LibboxStatusMessage?) {}

        func writeGroups(_ groupIterator: LibboxOutboundGroupIteratorProtocol?) {
            groupListView.setGroups(groupIterator!)
        }
    }
}
