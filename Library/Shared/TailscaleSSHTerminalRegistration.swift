import Foundation

/// Library can't import TerminalWrapper (TerminalWrapper depends on Library and
/// requires a higher deployment target), so app targets register the terminal
/// view via runtime lookup.
public enum TailscaleSSHTerminalRegistration {
    public static func registerIfAvailable() {
        if #available(iOS 17.0, macOS 14.0, *) {
            guard let cls = NSClassFromString("TerminalWrapperBootstrap") as? NSObject.Type else {
                return
            }
            _ = cls.perform(Selector(("register")))
        }
    }
}
