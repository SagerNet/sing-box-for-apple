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
struct TailsshTerminalSurfaceView: View {
    let state: TerminalViewState
    let extras: TailsshTerminalExtras
    var isActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Representable(state: state, extras: extras, isActive: isActive)
            .onChange(of: colorScheme) { newScheme in
                state.adopt(colorScheme: newScheme)
            }
            .onAppear {
                state.adopt(colorScheme: colorScheme)
            }
    }

    #if canImport(AppKit)
        private struct Representable: NSViewRepresentable {
            let state: TerminalViewState
            let extras: TailsshTerminalExtras
            var isActive: Bool = true

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
            var isActive: Bool = true

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
                if isActive, !view.isFirstResponder {
                    view.becomeFirstResponder()
                }
            }
        }
    #endif
}
