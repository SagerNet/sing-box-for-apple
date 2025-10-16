import SwiftUI

public struct DashboardCardView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let title: String
    private let isHalfWidth: Bool
    @ViewBuilder private let content: () -> Content

    public init(title: String, isHalfWidth: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isHalfWidth = isHalfWidth
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
            .padding(EdgeInsets(top: 20, leading: 26, bottom: 20, trailing: 26))
        #else
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        #endif
            .modifier(CardStyleModifier(colorScheme: colorScheme))
    }
}

private struct CardStyleModifier: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        } else {
            content
                .background(backgroundColor)
                .cornerRadius(16)
        }
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
