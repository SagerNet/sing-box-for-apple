import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    final class WindowReportingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(self?.window)
            }
        }
    }

    let callback: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindowChange = callback
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context _: Context) {
        nsView.onWindowChange = callback
        DispatchQueue.main.async {
            callback(nsView.window)
        }
    }
}
