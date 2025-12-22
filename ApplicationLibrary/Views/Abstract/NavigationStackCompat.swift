import SwiftUI

public struct NavigationStackCompat<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 17.0, macOS 13.0, tvOS 17.0, *) {
            // view not updating in iOS 16, but why?
            NavigationStackWithPath {
                content
            }
        } else {
            NavigationView {
                content
            }
            #if !os(macOS)
            .navigationViewStyle(.stack)
            #endif
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
private struct NavigationStackWithPath<Content: View>: View {
    private let content: Content
    @State private var path = NavigationPath()

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $path.animation(.linear(duration: 0))) {
            content
        }
    }
}
