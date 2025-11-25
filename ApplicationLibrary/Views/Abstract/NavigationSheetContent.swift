import Library
import SwiftUI

@MainActor
public struct SheetContent<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        #if os(iOS) || os(tvOS)
            NavigationStackCompat {
                content
                    .navigationTitle(title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            .presentationDetentsIfAvailable()
        #endif
    }
}

@MainActor
public struct GroupsSheetContent: View {
    public init() {}

    public var body: some View {
        SheetContent("Groups") {
            GroupListView()
        }
    }
}

@MainActor
public struct ConnectionsSheetContent: View {
    public init() {}

    public var body: some View {
        SheetContent("Connections") {
            ConnectionListView()
        }
    }
}
