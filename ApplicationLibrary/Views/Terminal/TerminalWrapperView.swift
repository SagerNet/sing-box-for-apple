#if canImport(GhosttyTerminal) && os(macOS)
    import GhosttyTerminal
    import Library
    import SwiftUI

    @MainActor
    public struct TerminalWrapperView: View {
        private let presentedSession: TailscaleSSHPresentedSession
        @EnvironmentObject private var peerStore: TailscaleSSHPeerStore
        @Environment(\.openWindow) private var openWindow

        public init(_ presentedSession: TailscaleSSHPresentedSession) {
            self.presentedSession = presentedSession
        }

        public var body: some View {
            TerminalSessionView(presentedSession)
                .focusedSceneValue(\.newTerminalWindowAction, openDuplicateWindow)
                .focusedSceneValue(\.openTerminalWindowAction) { [openWindow] newSession in
                    openWindow(value: newSession)
                }
                .focusedSceneValue(\.currentTerminalSession, presentedSession)
                .focusedSceneValue(\.quickConnectPeers, peerStore.quickConnectPeers)
        }

        private func openDuplicateWindow() {
            openWindow(value: TailscaleSSHPresentedSession(
                endpointTag: presentedSession.endpointTag,
                peerDisplayName: presentedSession.peerDisplayName,
                peerAddress: presentedSession.peerAddress,
                username: presentedSession.username,
                terminalType: presentedSession.terminalType,
                hostKeys: presentedSession.hostKeys,
                forwardAgent: presentedSession.forwardAgent
            ))
        }
    }

    @MainActor
    private struct TerminalSessionView: View {
        @StateObject private var viewModel = TerminalWrapperViewModel()
        private let presentedSession: TailscaleSSHPresentedSession
        @Environment(\.dismiss) private var closeWindow
        @Environment(\.openURL) private var openURL

        init(_ presentedSession: TailscaleSSHPresentedSession) {
            self.presentedSession = presentedSession
        }

        var body: some View {
            TerminalSessionContentView(
                viewModel: viewModel,
                presentedSession: presentedSession,
                onCloseSession: { closeWindow() }
            )
            .navigationTitle(displayedTitle)
            .onAppear {
                viewModel.onWindowClose = { closeWindow() }
                viewModel.extras.onOpenURL = { urlString, _ in
                    guard let url = URL(string: urlString) else { return }
                    openURL(url)
                }
            }
            .task {
                await viewModel.start(presentedSession)
            }
            .onDisappear {
                Task { await viewModel.disconnect() }
            }
        }

        private var displayedTitle: String {
            TerminalSessionContentView.displayTitle(
                phase: viewModel.phase,
                extrasTitle: viewModel.extras.title,
                peerDisplayName: presentedSession.peerDisplayName
            )
        }
    }
#endif
