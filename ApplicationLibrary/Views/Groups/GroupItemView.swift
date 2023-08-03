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
        Button(action: {
            if group.selectable, group.selected != item.tag {
                Task.detached {
                    selectOutbound()
                }
            }
        }, label: {
            HStack {
                VStack {
                    HStack {
                        Text(item.tag)
                            .font(.caption)
                            .foregroundStyle(.foreground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 8)
                    HStack {
                        Text(item.type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
                VStack {
                    if group.selected == item.tag {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 0)
                    if item.urlTestDelay > 0 {
                        Text(item.delayString)
                            .font(.caption)
                            .foregroundColor(item.delayColor)
                    }
                }
            }
        })
        #if !os(tvOS)
        .buttonStyle(.borderless)
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(backgroundColor)
        .cornerRadius(10)
        #endif
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
