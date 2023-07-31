import SwiftUI

public func NavigationStackCompat<T>(@ViewBuilder content: () -> T) -> some View where T: View{
    viewBuilder {
        if #available(iOS 17.0, *) {
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
