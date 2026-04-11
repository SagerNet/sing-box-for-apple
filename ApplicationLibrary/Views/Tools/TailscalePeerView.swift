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

    @State private var copiedAddress: String?
    @StateObject private var pingViewModel = TailscalePingViewModel()

    public init(peer: TailscalePeerData, endpointTag: String, isSelf: Bool) {
        self.peer = peer
        self.endpointTag = endpointTag
        self.isSelf = isSelf
    }

    public var body: some View {
        FormView {
            Section("Tailscale Addresses") {
                if !peer.dnsName.isEmpty {
                    addressRow(LibboxFormatFQDN(peer.dnsName), label: "MagicDNS")
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

            if peer.keyExpiry > 0 || !peer.os.isEmpty || peer.exitNode {
                Section("Details") {
                    if peer.keyExpiry > 0 {
                        FormTextItem("Key Expiry", "key") {
                            Text(keyExpiryText)
                        }
                    }
                    if !peer.os.isEmpty {
                        FormTextItem("OS", "desktopcomputer") {
                            Text(peer.os)
                        }
                    }
                    if peer.exitNode {
                        FormTextItem("Exit Node", "arrow.triangle.turn.up.right.diamond") {
                            Text("Active")
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(peer.hostName)
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
        }
        .onDisappear {
            if pingViewModel.isRunning {
                pingViewModel.stop()
            }
        }
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
