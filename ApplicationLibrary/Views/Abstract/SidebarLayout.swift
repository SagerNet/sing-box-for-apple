#if os(iOS)
    import SwiftUI

    public enum SidebarLayout {
        public static func isEnabled(_ horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
            if #available(iOS 16.0, *) {
                return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
            }
            return false
        }
    }
#endif
