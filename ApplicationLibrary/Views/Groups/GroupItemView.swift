import Libbox
import Library
import SwiftUI

public struct GroupItemView: View {
    private let _group: Binding<OutboundGroup>
    private var group: OutboundGroup {
        _group.wrappedValue
    }

    private let item: OutboundGroupItem
    public init(_ group: Binding<OutboundGroup>, _ item: OutboundGroupItem) {
        _group = group
        self.item = item
    }

    @State private var alert: Alert?

    public var body: some View {
        HStack {
            if group.selected == item.tag {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 6)
            } else {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 6)
            }
            VStack {
                HStack {
                    Text(item.tag)
                        .truncationMode(.tail)
                        .lineLimit(1)
                        .font(.system(size: 14))
                    Spacer(minLength: 6)
                }
                Spacer(minLength: 6)
                HStack(alignment: .center) {
                    Text(item.type)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Spacer(minLength: 6)
                    if item.urlTestDelay > 0 {
                        Text(item.delayString)
                            .foregroundColor(item.delayColor)
                            .font(.system(size: 11))
                    }
                }
            }
            .frame(height: 36)
            .padding([.top, .bottom, .trailing], 12)
        }
        .background(backgroundColor)
        .onTapGesture {
            if group.selectable, group.selected != item.tag {
                Task.detached {
                    selectOutbound()
                }
            }
        }
        .alertBinding($alert)
    }

    private func selectOutbound() {
        do {
            try LibboxNewStandaloneCommandClient()!.selectOutbound(group.tag, outboundTag: item.tag)
            var newGroup = group
            newGroup.selected = item.tag
            _group.wrappedValue = newGroup
        } catch {
            alert = Alert(error)
            return
        }
    }

    private var backgroundColor: Color {
        #if os(iOS)
            return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
            return Color(nsColor: .textBackgroundColor)
        #elseif os(tvOS)
            return Color.black
        #endif
    }
}
