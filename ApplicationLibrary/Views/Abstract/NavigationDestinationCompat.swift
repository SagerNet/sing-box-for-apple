import SwiftUI

func NavigationDestinationCompat(isPresented: Binding<Bool>, @ViewBuilder destination: () -> some View) -> some View {
    if #unavailable(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0) {
        return NavigationLink(
            destination: destination(),
            isActive: isPresented,
            label: {
                EmptyView()
            }
        )
    } else {
        return EmptyView().navigationDestination(isPresented: isPresented, destination: destination)
    }
}
