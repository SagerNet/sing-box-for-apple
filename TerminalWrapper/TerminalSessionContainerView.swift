#if os(iOS)
    import GhosttyTerminal
    import Library
    import SwiftUI
    #if !targetEnvironment(macCatalyst)
        import UIKit
    #endif

    @available(iOS 17.0, *)
    @MainActor
    struct TerminalSessionContainerView: View {
        @StateObject private var sessionManager = TerminalSessionManager()
        private let initialSession: TailscaleSSHPresentedSession
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL

        init(_ initialSession: TailscaleSSHPresentedSession) {
            self.initialSession = initialSession
        }

        var body: some View {
            ZStack {
                ForEach(sessionManager.sessions) { managed in
                    let isActive = managed.id == sessionManager.activeSessionID
                    TerminalSessionContentView(
                        viewModel: managed.viewModel,
                        presentedSession: managed.presentedSession,
                        isActive: isActive,
                        onCloseSession: { sessionManager.closeSession(id: managed.id) }
                    )
                    .opacity(isActive ? 1 : 0)
                    .zIndex(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .onAppear {
                        setupCallbacks(for: managed)
                    }
                }
            }
            .navigationTitle(sessionManager.activeDisplayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    TerminalSessionMenuButton(sessionManager: sessionManager)
                }
            }
            .background(
                Button("") {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.closeSession(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            )
            .background(
                Button("") {
                    sessionManager.createDuplicateSession()
                }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            )
            .onAppear {
                sessionManager.onDismissAll = { dismiss() }
                sessionManager.addSession(from: initialSession)
            }
            .onDisappear {
                sessionManager.disconnectAll()
            }
        }

        private func setupCallbacks(for managed: TerminalSessionManager.ManagedSession) {
            managed.viewModel.extras.onOpenURL = { urlString, _ in
                guard let url = URL(string: urlString) else { return }
                openURL(url)
            }
            #if !targetEnvironment(macCatalyst)
                managed.viewModel.extras.onRequestTextSelection = { request in
                    presentTerminalSelectionSheet(request: request)
                }
            #endif
        }

        #if !targetEnvironment(macCatalyst)
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
#endif
