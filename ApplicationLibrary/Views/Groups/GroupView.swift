import Library
import SwiftUI

enum GroupsLayout {
    #if os(tvOS)
        static let dotSize: CGFloat = 33
        static let dotSpacing: CGFloat = 12
        static let dotCornerRadius: CGFloat = 12
        static let selectedDotSize: CGFloat = 12
        static let itemMinWidth: CGFloat = 320
    #else
        static let dotSize: CGFloat = 11
        static let dotSpacing: CGFloat = 4
        static let dotCornerRadius: CGFloat = 4
        static let selectedDotSize: CGFloat = 4
        static let itemMinWidth: CGFloat = 170
    #endif
}

@MainActor
public struct GroupHeaderView: View {
    @EnvironmentObject private var listViewModel: GroupListViewModel

    private let group: OutboundGroup

    public init(group: OutboundGroup) {
        self.group = group
    }

    private var isTesting: Bool {
        listViewModel.testingGroups.contains(group.tag)
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(group.tag)
                .font(.headline)
            Text(group.displayType)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: "\(group.items.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .background(Color.urlTestNeutral)
                .clipShape(Capsule())
            HStack(spacing: 16) {
                Button {
                    listViewModel.performGroupURLTest(group.tag)
                } label: {
                    Group {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                    }
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .disabled(isTesting)
                #if os(macOS) || os(tvOS)
                    .buttonStyle(.plain)
                #else
                    .buttonStyle(.borderless)
                #endif
                Button {
                    listViewModel.toggleExpand(groupTag: group.tag)
                } label: {
                    Image(systemName: group.isExpand ? "chevron.up" : "chevron.down")
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                #if os(macOS) || os(tvOS)
                .buttonStyle(.plain)
                #else
                .buttonStyle(.borderless)
                #endif
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(tvOS)
            .contentShape(Rectangle())
            .onTapGesture {
                listViewModel.toggleExpand(groupTag: group.tag)
            }
        #endif
            .cardSegment(top: true, bottom: false)
    }
}

@MainActor
public struct GroupContentView: View {
    @EnvironmentObject private var listViewModel: GroupListViewModel

    private let group: OutboundGroup
    private let contentWidth: CGFloat

    public init(group: OutboundGroup, contentWidth: CGFloat) {
        self.group = group
        self.contentWidth = contentWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.isExpand {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: GroupsLayout.itemMinWidth), spacing: 10)], spacing: 10) {
                    ForEach(group.items, id: \.tag) { item in
                        GroupItemView(
                            groupTag: group.tag,
                            selectable: group.selectable,
                            isSelected: group.selected == item.tag,
                            item: item
                        )
                    }
                }
            } else {
                dotGrid
                #if !os(tvOS)
                .contentShape(Rectangle())
                .onTapGesture {
                    listViewModel.toggleExpand(groupTag: group.tag)
                }
                #endif
            }
        }
        .padding(EdgeInsets(top: 2, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSegment(top: false, bottom: true)
    }

    private var dotGrid: some View {
        let columns = max(1, Int((contentWidth + GroupsLayout.dotSpacing) / (GroupsLayout.dotSize + GroupsLayout.dotSpacing)))
        let horizontalSpacing: CGFloat
        if columns > 1 {
            horizontalSpacing = (contentWidth - CGFloat(columns) * GroupsLayout.dotSize) / CGFloat(columns - 1)
        } else {
            horizontalSpacing = 0
        }
        let rows = (group.items.count + columns - 1) / columns
        let height = CGFloat(rows) * GroupsLayout.dotSize + CGFloat(max(0, rows - 1)) * GroupsLayout.dotSpacing
        return Canvas { context, _ in
            for (index, item) in group.items.enumerated() {
                let x = CGFloat(index % columns) * (GroupsLayout.dotSize + horizontalSpacing)
                let y = CGFloat(index / columns) * (GroupsLayout.dotSize + GroupsLayout.dotSpacing)
                let rect = CGRect(x: x, y: y, width: GroupsLayout.dotSize, height: GroupsLayout.dotSize)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: GroupsLayout.dotCornerRadius),
                    with: .color(item.delayColor)
                )
                if item.tag == group.selected {
                    let inset = (GroupsLayout.dotSize - GroupsLayout.selectedDotSize) / 2
                    context.fill(
                        Path(ellipseIn: rect.insetBy(dx: inset, dy: inset)),
                        with: .color(.white)
                    )
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardSegmentShape: Shape {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
            radius: bottomRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

extension View {
    func cardSegment(top: Bool, bottom: Bool) -> some View {
        modifier(CardSegmentModifier(
            shape: CardSegmentShape(topRadius: top ? 16 : 0, bottomRadius: bottom ? 16 : 0)
        ))
    }
}

private struct CardSegmentModifier: ViewModifier {
    let shape: CardSegmentShape
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .clipShape(shape)
    }

    private var backgroundColor: Color {
        #if os(iOS)
            return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
            return Color(nsColor: .textBackgroundColor)
        #elseif os(tvOS)
            switch colorScheme {
            case .dark:
                return Color(uiColor: .black)
            default:
                return Color(uiColor: .white)
            }
        #else
            return Color.clear
        #endif
    }
}
