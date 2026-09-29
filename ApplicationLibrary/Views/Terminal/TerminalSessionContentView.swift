#if canImport(GhosttyTerminal)
    import GhosttyTerminal
    import Library
    import SwiftUI

    @MainActor
    struct TerminalSessionContentView: View {
        @ObservedObject var viewModel: TerminalWrapperViewModel
        let presentedSession: TailscaleSSHPresentedSession
        var isActive: Bool = true
        var onCloseSession: (() -> Void)?
        @Environment(\.dismiss) private var dismiss
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                if let terminalState = viewModel.terminalState {
                    TailsshTerminalSurfaceView(
                        state: terminalState,
                        extras: viewModel.extras,
                        isActive: isActive
                    )
                    .opacity(viewModel.hasReceivedOutput ? 1 : 0)
                }
                if viewModel.phase == .connecting || (viewModel.phase == .running && !viewModel.hasReceivedOutput) {
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
                        HStack(spacing: 12) {
                            Text(reason.displayText)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button("Close") {
                                if let onCloseSession {
                                    onCloseSession()
                                } else {
                                    dismiss()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    }
                }
            }
        }

        private var backgroundColor: Color {
            let themeColor = colorScheme == .dark ? viewModel.darkBackgroundColor : viewModel.lightBackgroundColor
            #if os(iOS)
                return themeColor ?? Color(uiColor: .systemBackground)
            #else
                return themeColor ?? Color(nsColor: .windowBackgroundColor)
            #endif
        }

        var displayedTitle: String {
            Self.displayTitle(
                phase: viewModel.phase,
                extrasTitle: viewModel.extras.title,
                peerDisplayName: presentedSession.peerDisplayName
            )
        }

        static func displayTitle(
            phase: TerminalWrapperViewModel.Phase,
            extrasTitle: String,
            peerDisplayName: String
        ) -> String {
            if case .connecting = phase {
                return peerDisplayName
            }
            let remote = extrasTitle.trimmingCharacters(in: .whitespaces)
            return remote.isEmpty ? peerDisplayName : remote
        }

        static func bannerAttributedString(_ text: String) -> AttributedString {
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
#endif
