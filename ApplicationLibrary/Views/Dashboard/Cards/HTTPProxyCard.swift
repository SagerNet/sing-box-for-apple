import Library
import SwiftUI

public struct HTTPProxyCard: View {
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool
    private let onToggle: (Bool) async -> Void

    public init(
        systemProxyAvailable: Binding<Bool>,
        systemProxyEnabled: Binding<Bool>,
        onToggle: @escaping (Bool) async -> Void
    ) {
        _systemProxyAvailable = systemProxyAvailable
        _systemProxyEnabled = systemProxyEnabled
        self.onToggle = onToggle
    }

    public var body: some View {
        DashboardCardView(title: "", isHalfWidth: false) {
            Toggle("System HTTP Proxy", isOn: $systemProxyEnabled)
                .onChangeCompat(of: systemProxyEnabled) { newValue in
                    Task {
                        await onToggle(newValue)
                    }
                }
        }
    }
}
