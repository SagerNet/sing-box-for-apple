import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: StandaloneApplicationDelegate

    var body: some Scene {
        MacApplication()
    }
}
