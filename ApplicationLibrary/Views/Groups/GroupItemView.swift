import Library
import SwiftUI

@MainActor
public struct GroupItemView: View {
    @EnvironmentObject private var listViewModel: GroupListViewModel
    @Binding private var group: OutboundGroup

    private let itemTag: String
    private var item: OutboundGroupItem {
        group.items.first { $0.tag == itemTag }!
    }

    public init(_ group: Binding<OutboundGroup>, _ item: OutboundGroupItem) {
        _group = group
        itemTag = item.tag
    }

    public var body: some View {
        Button {
            if group.selectable, group.selected != item.tag {
                listViewModel.selectOutbound(groupTag: group.tag, outboundTag: item.tag)
            }
        } label: {
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
                        Text(item.displayType)
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
        }
        #if !os(tvOS)
        .buttonStyle(.borderless)
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        #endif
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
