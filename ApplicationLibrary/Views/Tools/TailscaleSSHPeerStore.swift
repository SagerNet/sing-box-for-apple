import Library
import SwiftUI

@MainActor
public final class TailscaleSSHPeerStore: ObservableObject {
    @Published public var sshPeers: [TailscaleSSHPeerEntry] = []
    @Published public var quickConnectPeerIDs: Set<String> = []

    public var quickConnectPeers: [TailscaleSSHPeerEntry] {
        sshPeers.filter { quickConnectPeerIDs.contains($0.stableID) }
    }

    public init() {}
}
