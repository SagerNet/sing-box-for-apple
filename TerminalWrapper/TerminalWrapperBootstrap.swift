import Library
import SwiftUI

@objc(TerminalWrapperBootstrap)
@available(iOS 17.0, macOS 14.0, *)
public final class TerminalWrapperBootstrap: NSObject {
    @objc public static func register() {
        Task { @MainActor in
            TailscaleSSHLaunchService.shared.terminalViewMaker = { presentedSession in
                AnyView(TerminalWrapperView(presentedSession))
            }
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
