import SwiftUI

@MainActor
public final class TailscaleSSHLaunchService {
    public static let shared = TailscaleSSHLaunchService()

    public var terminalViewMaker: ((TailscaleSSHPresentedSession) -> AnyView)?
    public var ghosttyThemePickerMaker: ((_ isDark: Bool, _ currentName: String, _ onSelect: @escaping (String) -> Void) -> AnyView)?

    public var sshPeers: [TailscaleSSHPeerEntry] = []
    public var quickConnectPeerIDs: Set<String> = []

    public var quickConnectPeers: [TailscaleSSHPeerEntry] {
        sshPeers.filter { quickConnectPeerIDs.contains($0.stableID) }
    }

    private init() {}
}
