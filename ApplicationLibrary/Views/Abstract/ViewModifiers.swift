import SwiftUI

public struct PlatformSheetSize {
    let minWidth: CGFloat
    let minHeight: CGFloat

    public init(minWidth: CGFloat, minHeight: CGFloat) {
        self.minWidth = minWidth
        self.minHeight = minHeight
    }

    public static let `default` = PlatformSheetSize(minWidth: 500, minHeight: 400)
    public static let small = PlatformSheetSize(minWidth: 400, minHeight: 300)
}

public extension View {
    func platformSheet(
        isPresented: Binding<Bool>,
        size: PlatformSheetSize = .default,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(PlatformSheetModifier(isPresented: isPresented, size: size, content: content))
    }

    func platformSheet<Item: Identifiable>(
        item: Binding<Item?>,
        size: PlatformSheetSize = .default,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        modifier(PlatformSheetItemModifier(item: item, size: size, content: content))
    }
}

private struct PlatformSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let size: PlatformSheetSize
    @ViewBuilder let content: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(iOS)
            content.sheet(isPresented: $isPresented) {
                NavigationStackCompat {
                    self.content()
                }
            }
        #elseif os(macOS)
            content.sheet(isPresented: $isPresented) {
                NavigationStackCompat {
                    self.content()
                }
                .frame(minWidth: size.minWidth, minHeight: size.minHeight)
            }
        #elseif os(tvOS)
            content.fullScreenCover(isPresented: $isPresented) {
                NavigationStackCompat {
                    self.content()
                }
            }
        #endif
    }
}

private struct PlatformSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let size: PlatformSheetSize
    @ViewBuilder let content: (Item) -> SheetContent

    func body(content: Content) -> some View {
        #if os(iOS)
            content.sheet(item: $item) { item in
                NavigationStackCompat {
                    self.content(item)
                }
            }
        #elseif os(macOS)
            content.sheet(item: $item) { item in
                NavigationStackCompat {
                    self.content(item)
                }
                .frame(minWidth: size.minWidth, minHeight: size.minHeight)
            }
        #elseif os(tvOS)
            content.fullScreenCover(item: $item) { item in
                NavigationStackCompat {
                    self.content(item)
                }
            }
        #endif
    }
}

public extension View {
    @ViewBuilder
    func presentationDetentsIfAvailable() -> some View {
        #if os(iOS) || os(tvOS)
            if #available(iOS 16.0, tvOS 17.0, *) {
                presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                self
            }
        #else
            self
        #endif
    }

    #if os(iOS) || os(tvOS)
        @available(iOS 16.0, tvOS 17.0, *)
        @ViewBuilder
        func presentationDetentsIfAvailable(_ detents: PresentationDetent...) -> some View {
            let detentSet: Set<PresentationDetent> = detents.isEmpty ? [.large] : Set(detents)
            presentationDetents(detentSet)
                .presentationDragIndicator(.visible)
        }
    #endif

    @ViewBuilder
    func actionButtonStyle() -> some View {
        #if os(tvOS)
            ActionButtonWrapper { self }
        #else
            if #available(iOS 26.0, macOS 26.0, *) {
                frame(width: 44, height: 32)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
            } else {
                frame(width: 44, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        #endif
    }
}

#if os(tvOS)
    private struct ActionButtonWrapper<Content: View>: View {
        @Environment(\.isFocused) private var isFocused
        let content: () -> Content

        var body: some View {
            content()
                .frame(width: 70, height: 48)
                .background(isFocused ? Color.secondary.opacity(0.3) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focusEffectDisabled()
        }
    }
#endif

public extension View {
    @ViewBuilder
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}

private struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

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
