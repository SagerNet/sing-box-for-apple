import Libbox
import Library
import SwiftUI

@MainActor
public class GroupViewModel: ObservableObject {
    @Published public var group: OutboundGroup
    @Published public var alert: Alert?

    public init(group: OutboundGroup) {
        self.group = group
    }

    public func toggleExpand() {
        group.isExpand = !group.isExpand
        Task {
            await setGroupExpand()
        }
    }

    public func performURLTest() {
        Task {
            await doURLTest()
        }
    }

    private nonisolated func doURLTest() async {
        do {
            try await LibboxNewStandaloneCommandClient()!.urlTest(group.tag)
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }

    private nonisolated func setGroupExpand() async {
        do {
            try await LibboxNewStandaloneCommandClient()!.setGroupExpand(group.tag, isExpand: group.isExpand)
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
