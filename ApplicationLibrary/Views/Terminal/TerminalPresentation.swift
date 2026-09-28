#if os(iOS) || os(macOS)
    import Library
    import SwiftUI
    #if os(iOS)
        import UIKit
    #endif

    extension View {
        @ViewBuilder
        func terminalPresentation(item session: Binding<TailscaleSSHPresentedSession?>) -> some View {
            #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    fullScreenCover(item: session) { presented in
                        NavigationStackCompat {
                            TerminalSessionContainerView(presented)
                        }
                    }
                } else {
                    sheet(item: session) { presented in
                        NavigationStackCompat {
                            TerminalSessionContainerView(presented)
                        }
                    }
                }
            #else
                modifier(TerminalWindowPresentationModifier(session: session))
            #endif
        }
    }

    #if os(macOS)
        private struct TerminalWindowPresentationModifier: ViewModifier {
            @Binding var session: TailscaleSSHPresentedSession?
            @Environment(\.openWindow) private var openWindow

            func body(content: Content) -> some View {
                content.onChangeCompat(of: session) { newValue in
                    guard let newValue else { return }
                    openWindow(value: newValue)
                    session = nil
                }
            }
        }
    #endif
#endif
