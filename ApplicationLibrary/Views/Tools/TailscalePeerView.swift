import Libbox
import Library
import SwiftUI

#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

@MainActor
public struct TailscalePeerView: View {
    let peer: TailscalePeerData
    let endpointTag: String
    let isSelf: Bool
    let networkName: String
    let canLogout: Bool
    let onLogout: (() -> Void)?

    @State private var copiedAddress: String?
    @StateObject private var pingViewModel = TailscalePingViewModel()
    #if !os(tvOS)
        @State private var sshPromptPresented = false
        @State private var sshPresentedSession: TailscaleSSHPresentedSession?
        @State private var pendingSSHSession: TailscaleSSHPresentedSession?
    #endif
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    public init(peer: TailscalePeerData, endpointTag: String, isSelf: Bool, networkName: String = "", canLogout: Bool = false, onLogout: (() -> Void)? = nil) {
        self.peer = peer
        self.endpointTag = endpointTag
        self.isSelf = isSelf
        self.networkName = networkName
        self.canLogout = canLogout
        self.onLogout = onLogout
    }

    public var body: some View {
        FormView {
            if isSelf, !networkName.isEmpty || (canLogout && onLogout != nil) {
                Section("Network") {
                    if !networkName.isEmpty {
                        addressRow(networkName, label: "Network")
                    }
                    if canLogout, let onLogout {
                        FormButton(role: .destructive) {
                            onLogout()
                        } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            Section("Tailscale Addresses") {
                if !peer.dnsName.isEmpty {
                    addressRow(LibboxFormatFQDN(peer.dnsName), label: "MagicDNS")
                }
                if !peer.hostName.isEmpty {
                    addressRow(peer.hostName, label: String(localized: "Hostname"))
                }
                ForEach(Array(peer.tailscaleIPs.enumerated()), id: \.offset) { _, ip in
                    if ip.contains(":") {
                        addressRow(ip, label: "IPv6")
                    } else {
                        addressRow(ip, label: "IPv4")
                    }
                }
            }

            if !isSelf, peer.online, let peerIP = peer.tailscaleIPs.first {
                Section {
                    if pingViewModel.hasResult {
                        connectionTypeRow
                    }
                    if pingViewModel.isRunning, pingViewModel.hasResult {
                        pingChartView
                    }
                    if !pingViewModel.hasResult {
                        Text("No data")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Ping")
                        Spacer()
                        ActionIconButton(pingViewModel.isRunning ? "stop.fill" : "play.fill") {
                            if pingViewModel.isRunning {
                                pingViewModel.stop()
                            } else {
                                pingViewModel.start(endpointTag: endpointTag, peerIP: peerIP)
                            }
                        }
                        .textCase(nil)
                    }
                }
            }

            Section("Details") {
                if peer.expired {
                    FormTextItem("Key Expiry", "key") {
                        Text("Expired")
                            .foregroundStyle(.red)
                    }
                } else if peer.keyExpiry > 0 {
                    FormTextItem("Key Expiry", "key") {
                        Text(keyExpiryText)
                    }
                } else {
                    FormTextItem("Key Expiry", "key") {
                        Text("Disabled")
                            .foregroundStyle(.secondary)
                    }
                }
                if !peer.os.isEmpty {
                    FormTextItem("OS", "desktopcomputer") {
                        Text(peer.os)
                    }
                }
                if !peer.online, peer.lastSeen > 0 {
                    FormTextItem("Last Seen", "clock") {
                        Text(lastSeenText)
                    }
                }
                if peer.exitNode {
                    FormTextItem("Exit Node", "arrow.triangle.turn.up.right.diamond") {
                        Text("Active")
                    }
                } else if peer.exitNodeOption {
                    FormTextItem("Exit Node", "arrow.triangle.turn.up.right.diamond") {
                        Text("Available")
                    }
                }
                if peer.shareeNode {
                    FormTextItem("Shared in", "person.crop.circle.badge.exclamationmark") {
                        Text("Yes")
                    }
                }
                if !peer.sshHostKeys.isEmpty {
                    #if !os(tvOS)
                        if peer.online, !isSelf, !peer.tailscaleIPs.isEmpty {
                            FormButton {
                                sshPromptPresented = true
                            } label: {
                                HStack {
                                    Label("Connect via SSH", systemImage: "terminal")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } else {
                            FormTextItem("SSH", "terminal") {
                                Text("Available")
                            }
                        }
                    #else
                        FormTextItem("SSH", "terminal") {
                            Text("Available")
                        }
                    #endif
                }
            }
        }
        .navigationTitle(peer.displayName)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #elseif os(macOS)
            .navigationSubtitle(peer.online ? String(localized: "Connected") : String(localized: "Not Connected"))
        #endif
            .toolbar {
                #if !os(macOS)
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 4) {
                            Text(peer.displayName)
                                .font(.headline)
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(peer.online ? .green : Color(.systemGray))
                                Text(peer.online ? "Connected" : "Not Connected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                #endif
            }
            .onDisappear {
                if pingViewModel.isRunning {
                    pingViewModel.stop()
                }
            }
        #if !os(tvOS)
            .platformSheet(isPresented: $sshPromptPresented, size: PlatformSheetSize(minWidth: 360, minHeight: 220), onDismiss: {
                if let session = pendingSSHSession {
                    pendingSSHSession = nil
                    sshPresentedSession = session
                }
            }) {
                TailscaleSSHPromptView(
                    peer: peer,
                    endpointTag: endpointTag,
                    onConnect: { session in pendingSSHSession = session }
                )
            }
            #if os(iOS)
            .sheet(item: $sshPresentedSession) { presented in
                NavigationStackCompat {
                    TerminalSessionContainerView(presented)
                }
            }
            #elseif os(macOS)
            .onChangeCompat(of: sshPresentedSession) { newValue in
                guard let newValue else { return }
                openWindow(value: newValue)
                sshPresentedSession = nil
            }
            #endif
        #endif
    }

    private var connectionTypeRow: some View {
        HStack(spacing: 8) {
            if pingViewModel.isDirect {
                Image(systemName: "arrow.right")
                    .foregroundStyle(.green)
                Text("Direct connection")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                Text("DERP-relayed connection")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(verbatim: "\(Int(pingViewModel.latencyMs)) ms")
                .font(.headline)
        }
    }

    private var pingChartView: some View {
        #if os(tvOS)
            let chartHeight: CGFloat = 160
            let labelWidth: CGFloat = 80
        #else
            let chartHeight: CGFloat = 80
            let labelWidth: CGFloat = 50
        #endif
        return HStack(alignment: .center) {
            TrafficLineChart(
                data: pingViewModel.latencyHistory,
                lineColor: pingViewModel.isDirect ? .green : .blue,
                chartHeight: chartHeight
            )
            VStack(alignment: .trailing, spacing: 0) {
                let maxMs = max(Int((pingViewModel.latencyHistory.max() ?? 1) * 1.2), 1)
                Text(verbatim: "\(maxMs)ms")
                Spacer()
                Text(verbatim: "\(maxMs * 2 / 3)ms")
                Spacer()
                Text(verbatim: "\(maxMs / 3)ms")
                Spacer()
                Text(verbatim: "0ms")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: labelWidth)
        }
        .frame(height: chartHeight)
        #if os(tvOS)
            .padding(.vertical, 8)
        #endif
    }

    private var keyExpiryText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(peer.keyExpiry))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var lastSeenText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(peer.lastSeen))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func addressRow(_ address: String, label: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(address)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            #if !os(tvOS)
                Button {
                    copyToClipboard(address)
                } label: {
                    if copiedAddress == address {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.blue)
                    }
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            #endif
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation {
            copiedAddress = text
        }
        Task {
            try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
            withAnimation {
                if copiedAddress == text {
                    copiedAddress = nil
                }
            }
        }
    }
}
