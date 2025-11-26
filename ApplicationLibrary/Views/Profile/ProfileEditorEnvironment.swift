#if os(iOS) || os(macOS)
    import SwiftUI

    public struct ProfileEditorKey: EnvironmentKey {
        public static let defaultValue: ((Binding<String>, Bool) -> AnyView)? = nil
    }

    public extension EnvironmentValues {
        var profileEditor: ((Binding<String>, Bool) -> AnyView)? {
            get { self[ProfileEditorKey.self] }
            set { self[ProfileEditorKey.self] = newValue }
        }
    }
#endif
