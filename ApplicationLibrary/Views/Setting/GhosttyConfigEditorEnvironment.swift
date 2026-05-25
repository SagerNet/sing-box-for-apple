import SwiftUI

public struct GhosttyConfigEditorKey: EnvironmentKey {
    public static let defaultValue: ((Binding<String>) -> AnyView)? = nil
}

public extension EnvironmentValues {
    var ghosttyConfigEditor: ((Binding<String>) -> AnyView)? {
        get { self[GhosttyConfigEditorKey.self] }
        set { self[GhosttyConfigEditorKey.self] = newValue }
    }
}
