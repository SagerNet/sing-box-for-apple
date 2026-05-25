import Foundation

/// Library can't import TerminalWrapper (TerminalWrapper depends on Library,
/// circular dependency), so app targets register the terminal view via runtime
/// lookup.
public enum TailscaleSSHTerminalRegistration {
    public static func registerIfAvailable() {
        guard let cls = NSClassFromString("TerminalWrapperBootstrap") as? NSObject.Type else {
            return
        }
        _ = cls.perform(Selector(("register")))
    }
}
