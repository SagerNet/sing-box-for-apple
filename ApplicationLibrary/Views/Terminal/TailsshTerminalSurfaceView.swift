#if canImport(GhosttyTerminal)
    import GhosttyTerminal
    import SwiftUI

    #if canImport(AppKit)
        import AppKit
    #elseif canImport(UIKit)
        import GameController
        import UIKit
    #endif

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

                func makeUIView(context _: Context) -> TailsshUITerminalView {
                    let view = TailsshUITerminalView(frame: .zero)
                    view.controller = state.controller
                    view.configuration = state.configuration
                    view.delegate = extras
                    return view
                }

                func updateUIView(_ view: TailsshUITerminalView, context _: Context) {
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

            final class TailsshUITerminalView: UITerminalView {
                private var interceptedPresses: Set<UIPress> = []

                override init(frame: CGRect) {
                    super.init(frame: frame)
                    NotificationCenter.default.addObserver(self, selector: #selector(hardwareKeyboardDidChange), name: .GCKeyboardDidConnect, object: nil)
                    NotificationCenter.default.addObserver(self, selector: #selector(hardwareKeyboardDidChange), name: .GCKeyboardDidDisconnect, object: nil)
                }

                @available(*, unavailable)
                required init?(coder _: NSCoder) {
                    fatalError()
                }

                override var inputAccessoryView: UIView? {
                    if GCKeyboard.coalesced != nil, (delegate as? TailsshTerminalExtras)?.alwaysShowsSymbolBar != true {
                        return nil
                    }
                    return super.inputAccessoryView
                }

                @objc private func hardwareKeyboardDidChange() {
                    reloadInputViews()
                }

                override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                    var remaining = presses
                    if let onCommandKey = (delegate as? TailsshTerminalExtras)?.onCommandKey {
                        for press in presses {
                            guard let key = press.key,
                                  key.modifierFlags.intersection([.command, .control, .alternate, .shift]) == .command,
                                  onCommandKey(key.charactersIgnoringModifiers.lowercased())
                            else { continue }
                            interceptedPresses.insert(press)
                            remaining.remove(press)
                        }
                    }
                    if !remaining.isEmpty {
                        super.pressesBegan(remaining, with: event)
                    }
                }

                override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                    let remaining = presses.subtracting(interceptedPresses)
                    interceptedPresses.subtract(presses)
                    if !remaining.isEmpty {
                        super.pressesEnded(remaining, with: event)
                    }
                }

                override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                    let remaining = presses.subtracting(interceptedPresses)
                    interceptedPresses.subtract(presses)
                    if !remaining.isEmpty {
                        super.pressesCancelled(remaining, with: event)
                    }
                }
            }
        #endif
    }
#endif
