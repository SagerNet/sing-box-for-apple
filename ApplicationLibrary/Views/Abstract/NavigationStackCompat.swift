import SwiftUI

public func NavigationStackCompat(@ViewBuilder content: () -> some View) -> some View {
    viewBuilder {
        if #available(iOS 17.0, macOS 13.0, tvOS 17.0, *) {
            // view not updating in iOS 16, but why?
            NavigationStack {
                content()
            }
        } else {
            NavigationView(content: content)
            #if !os(macOS)
                .navigationViewStyle(.stack)
            #endif
        }
    }
}
