import Library
import SwiftUI

@objc(TerminalWrapperBootstrap)
public final class TerminalWrapperBootstrap: NSObject {
    @objc public static func register() {
        Task { @MainActor in
            #if os(iOS)
                TailscaleSSHLaunchService.shared.terminalViewMaker = { presentedSession in
                    AnyView(TerminalSessionContainerView(presentedSession))
                }
            #else
                TailscaleSSHLaunchService.shared.terminalViewMaker = { presentedSession in
                    AnyView(TerminalWrapperView(presentedSession))
                }
            #endif
            #if !os(tvOS)
                TailscaleSSHLaunchService.shared.ghosttyThemePickerMaker = { isDark, currentName, onSelect in
                    AnyView(ThemePickerView(
                        scheme: isDark ? .dark : .light,
                        currentName: currentName,
                        onSelect: onSelect
                    ))
                }
            #endif
        }
    }
}
