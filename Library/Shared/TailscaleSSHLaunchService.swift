import SwiftUI

@MainActor
public final class TailscaleSSHLaunchService {
    public static let shared = TailscaleSSHLaunchService()

    public var terminalViewMaker: ((TailscaleSSHPresentedSession) -> AnyView)?
    public var ghosttyThemePickerMaker: ((_ isDark: Bool, _ currentName: String, _ onSelect: @escaping (String) -> Void) -> AnyView)?

    private init() {}
}
