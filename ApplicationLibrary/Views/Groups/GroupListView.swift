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
                            GroupView(it, Binding(get: {
                                groupExpand[it.tag] ?? it.selectable
                            }, set: { newValue in
                                groupExpand[it.tag] = newValue
                            }))
                            Spacer()
                        }
                    }.padding()
                }
            } else {
                Text("Empty groups")
            }
        }
        .onAppear(perform: doReload)
        .onDisappear {
            connectTask?.cancel()
            if let commandClient {
                try? commandClient.disconnect()
            }
            commandClient = nil
        }
        .navigationTitle("Groups")
    }

    private func doReload() {
        connectTask?.cancel()
        connectTask = Task.detached {
            await connect()
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
            groups.append(OutboundGroup(tag: goGroup.tag, type: goGroup.type, selected: goGroup.selected, selectable: goGroup.selectable, items: items))
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
