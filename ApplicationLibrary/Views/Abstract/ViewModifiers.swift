import SwiftUI

public extension View {
    @ViewBuilder
    func presentationDetentsIfAvailable() -> some View {
        #if os(iOS) || os(tvOS)
            if #available(iOS 16.0, tvOS 17.0, *) {
                self.presentationDetents([.large])
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
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            self.frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
    }
}
