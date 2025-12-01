import Libbox
import Library
import SwiftUI

@MainActor
public class GroupListViewModel: BaseViewModel {
    @Published public var groups: [OutboundGroup] = []

    private var pendingSelections: [String: String] = [:]

    override public init() {
        super.init()
        isLoading = true
    }

    public func connect() {
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
        }
    }

    public func setGroups(_ goGroups: [LibboxOutboundGroup]?) {
        guard let goGroups else { return }

        let existingGroups = Dictionary(uniqueKeysWithValues: groups.map { ($0.tag, $0) })

        var newGroups = [OutboundGroup]()
        for goGroup in goGroups {
            var items = [OutboundGroupItem]()
            let itemIterator = goGroup.getItems()!
            while itemIterator.hasNext() {
                let goItem = itemIterator.next()!
                items.append(OutboundGroupItem(
                    tag: goItem.tag,
                    type: goItem.type,
                    urlTestTime: Date(timeIntervalSince1970: Double(goItem.urlTestTime)),
                    urlTestDelay: UInt16(goItem.urlTestDelay)
                ))
            }

            var selected = goGroup.selected
            if let pending = pendingSelections[goGroup.tag] {
                if goGroup.selected == pending {
                    pendingSelections.removeValue(forKey: goGroup.tag)
                } else {
                    selected = pending
                }
            }

            let isExpand = existingGroups[goGroup.tag]?.isExpand ?? goGroup.isExpand

            newGroups.append(OutboundGroup(
                tag: goGroup.tag,
                type: goGroup.type,
                selected: selected,
                selectable: goGroup.selectable,
                isExpand: isExpand,
                items: items
            ))
        }
        groups = newGroups
        isLoading = false
    }

    public func selectOutbound(groupTag: String, outboundTag: String) {
        if let index = groups.firstIndex(where: { $0.tag == groupTag }) {
            groups[index].selected = outboundTag
        }
        pendingSelections[groupTag] = outboundTag

        Task {
            await doSelectOutbound(groupTag: groupTag, outboundTag: outboundTag)
        }
    }

    private nonisolated func doSelectOutbound(groupTag: String, outboundTag: String) async {
        do {
            try await LibboxNewStandaloneCommandClient()!.selectOutbound(groupTag, outboundTag: outboundTag)
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }

    public func toggleExpand(groupTag: String) {
        guard let index = groups.firstIndex(where: { $0.tag == groupTag }) else { return }
        groups[index].isExpand.toggle()
        let isExpand = groups[index].isExpand
        Task {
            await setGroupExpand(tag: groupTag, isExpand: isExpand)
        }
    }

    private nonisolated func setGroupExpand(tag: String, isExpand: Bool) async {
        do {
            try await LibboxNewStandaloneCommandClient()!.setGroupExpand(tag, isExpand: isExpand)
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }

    public func performURLTest(_ tag: String) {
        Task {
            await doURLTest(tag: tag)
        }
    }

    private nonisolated func doURLTest(tag: String) async {
        do {
            try await LibboxNewStandaloneCommandClient()!.urlTest(tag)
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }
}
