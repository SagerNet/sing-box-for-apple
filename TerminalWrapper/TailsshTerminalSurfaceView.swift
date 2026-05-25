import GhosttyTerminal
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Thin wrapper around AppTerminalView / UITerminalView that installs our
/// own forwarder delegate instead of the package's default (TerminalViewState),
/// so OpenURL / HoverLink / Progress callbacks reach us.
@available(iOS 17.0, macOS 14.0, *)
struct TailsshTerminalSurfaceView: View {
    let state: TerminalViewState
    let extras: TailsshTerminalExtras

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Representable(state: state, extras: extras)
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                state.adopt(colorScheme: newScheme)
            }
    }

    #if canImport(AppKit)
        private struct Representable: NSViewRepresentable {
            let state: TerminalViewState
            let extras: TailsshTerminalExtras

            func makeNSView(context _: Context) -> AppTerminalView {
                let view = AppTerminalView(frame: .zero)
                view.controller = state.controller
                view.configuration = state.configuration
                view.delegate = extras
                return view
            }

            func updateNSView(_ view: AppTerminalView, context _: Context) {
                if view.controller !== state.controller {
                    view.controller = state.controller
                }
                view.configuration = state.configuration
                if view.delegate !== extras {
                    view.delegate = extras
                }
            }
        }

    #elseif canImport(UIKit)
        private struct Representable: UIViewRepresentable {
            let state: TerminalViewState
            let extras: TailsshTerminalExtras

            func makeUIView(context _: Context) -> UITerminalView {
                let view = UITerminalView(frame: .zero)
                view.controller = state.controller
                view.configuration = state.configuration
                view.delegate = extras
                return view
            }

            func updateUIView(_ view: UITerminalView, context _: Context) {
                if view.controller !== state.controller {
                    view.controller = state.controller
                }
                view.configuration = state.configuration
                if view.delegate !== extras {
                    view.delegate = extras
                }
            }
        }
    #endif
}
