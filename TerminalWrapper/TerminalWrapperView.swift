import GhosttyTerminal
import Library
import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
    import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public struct TerminalWrapperView: View {
    @StateObject private var viewModel = TerminalWrapperViewModel()
    private let presentedSession: TailscaleSSHPresentedSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(_ presentedSession: TailscaleSSHPresentedSession) {
        self.presentedSession = presentedSession
    }

    public var body: some View {
        TerminalSessionContentView(
            viewModel: viewModel,
            presentedSession: presentedSession
        )
        .navigationTitle(displayedTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                }
            }
            .background(
                Button("") { dismiss() }
                    .keyboardShortcut("w", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
        #endif
            .onAppear {
                viewModel.onWindowClose = { dismiss() }
                viewModel.extras.onOpenURL = { urlString, _ in
                    guard let url = URL(string: urlString) else { return }
                    openURL(url)
                }
                #if os(iOS) && !targetEnvironment(macCatalyst)
                    viewModel.extras.onRequestTextSelection = { request in
                        presentTerminalSelectionSheet(request: request)
                    }
                #endif
                viewModel.start(presentedSession)
            }
            .onDisappear {
                viewModel.disconnect()
            }
    }

    private var displayedTitle: String {
        TerminalSessionContentView.displayTitle(
            phase: viewModel.phase,
            extrasTitle: viewModel.extras.title,
            peerHostName: presentedSession.peerHostName
        )
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        @MainActor
        private func presentTerminalSelectionSheet(request: TerminalTextSelectionRequest) {
            guard let presenter = topmostViewController() else { return }
            let selectionVC = TailsshTerminalSelectionViewController(
                text: request.text,
                anchorRange: request.anchorRange
            )
            selectionVC.onOpenURL = { url in
                openURL(url)
            }
            let nav = UINavigationController(rootViewController: selectionVC)
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            presenter.present(nav, animated: true)
        }

        @MainActor
        private func topmostViewController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene?.windows.first?.rootViewController
            else { return nil }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }
    #endif
}
