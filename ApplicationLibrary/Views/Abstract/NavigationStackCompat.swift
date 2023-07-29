import SwiftUI

public func NavigationStackCompat(@ViewBuilder content: () -> some View) -> some View {
    viewBuilder {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
            #if !os(macOS)
                .navigationViewStyle(.stack)
            #endif
        }
    }
}
