import Library
import SwiftUI

@MainActor
public struct GroupItemView: View {
    @EnvironmentObject private var listViewModel: GroupListViewModel

    private let groupTag: String
    private let selectable: Bool
    private let isSelected: Bool
    private let item: OutboundGroupItem

    public init(groupTag: String, selectable: Bool, isSelected: Bool, item: OutboundGroupItem) {
        self.groupTag = groupTag
        self.selectable = selectable
        self.isSelected = isSelected
        self.item = item
    }

    public var body: some View {
        Button {
            if selectable, !isSelected {
                listViewModel.selectOutbound(groupTag: groupTag, outboundTag: item.tag)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.tag)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    #if os(tvOS)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    #endif
                }
                HStack {
                    Text(item.displayType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if item.urlTestDelay > 0 {
                        Text(item.delayString)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundColor(item.delayColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if !os(tvOS)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .contentShape(Rectangle())
            #endif
        }
        #if !os(tvOS)
        .buttonStyle(.borderless)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(itemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.urlTestNeutral, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .contextMenu {
            Button {
                listViewModel.performURLTest(item.tag)
            } label: {
                Label("URLTest", systemImage: "bolt.fill")
            }
        }
        #endif
    }

    private var itemBackground: Color {
        #if os(iOS)
            return Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
            return Color(nsColor: .windowBackgroundColor)
        #else
            return Color.clear
        #endif
    }
}
