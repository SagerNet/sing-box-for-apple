import SwiftUI

func NavigationDestinationCompat(isPresented: Binding<Bool>, @ViewBuilder destination: () -> some View) -> some View {
    NavigationLink(
        destination: destination(),
        isActive: isPresented,
        label: {
            EmptyView()
        }
    )
}
