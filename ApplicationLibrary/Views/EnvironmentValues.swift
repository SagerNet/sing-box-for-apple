import Foundation
import Library
import SwiftUI

public extension EnvironmentValues {
    private struct showMenuBarExtraKey: EnvironmentKey {
        static let defaultValue: Binding<Bool> = .constant(true)
    }

    var showMenuBarExtra: Binding<Bool> {
        get {
            self[showMenuBarExtraKey.self]
        }
        set {
            self[showMenuBarExtraKey.self] = newValue
        }
    }

    private struct selectionKey: EnvironmentKey {
        static let defaultValue: Binding<NavigationPage> = .constant(.dashboard)
    }

    var selection: Binding<NavigationPage> {
        get {
            self[selectionKey.self]
        }
        set {
            self[selectionKey.self] = newValue
        }
    }

    private struct extensionProfileKey: EnvironmentKey {
        static let defaultValue: Binding<ExtensionProfile?> = .constant(nil)
    }

    var extensionProfile: Binding<ExtensionProfile?> {
        get {
            self[extensionProfileKey.self]
        }
        set {
            self[extensionProfileKey.self] = newValue
        }
    }

    private struct logClientKey: EnvironmentKey {
        static let defaultValue: Binding<LogClient?> = .constant(nil)
    }

    var logClient: Binding<LogClient?> {
        get {
            self[logClientKey.self]
        }
        set {
            self[logClientKey.self] = newValue
        }
    }
}
