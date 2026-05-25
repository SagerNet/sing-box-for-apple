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

    var body: some View {
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
                extras: viewModel.extras,
                isActive: isActive
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

    var displayedTitle: String {
        Self.displayTitle(
            phase: viewModel.phase,
            extrasTitle: viewModel.extras.title,
            peerHostName: presentedSession.peerHostName
        )
    }

    static func displayTitle(
        phase: TerminalWrapperViewModel.Phase,
        extrasTitle: String,
        peerHostName: String
    ) -> String {
        if case .connecting = phase {
            return peerHostName
        }
        let remote = extrasTitle.trimmingCharacters(in: .whitespaces)
        return remote.isEmpty ? peerHostName : remote
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
