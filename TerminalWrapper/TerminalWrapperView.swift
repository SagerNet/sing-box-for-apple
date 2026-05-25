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
        ZStack {
            #if os(iOS)
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            #elseif os(macOS)
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
            #endif
            TailsshTerminalSurfaceView(
                state: viewModel.terminalState,
                extras: viewModel.extras
            )
            if case .connecting = viewModel.phase {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    if let banner = viewModel.authBanner, !banner.isEmpty {
                        Text(Self.bannerAttributedString(banner))
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.primary)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                            .frame(maxWidth: 480)
                            .textSelection(.enabled)
                    }
                }
            } else if case let .finished(reason) = viewModel.phase {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text(reason.displayText)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }
        }
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
        if case .connecting = viewModel.phase {
            return presentedSession.peerHostName
        }
        let remote = viewModel.extras.title.trimmingCharacters(in: .whitespaces)
        return remote.isEmpty ? presentedSession.peerHostName : remote
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

    private static func bannerAttributedString(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: attributed) else { continue }
            attributed[range].link = url
            attributed[range].foregroundColor = .accentColor
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}
