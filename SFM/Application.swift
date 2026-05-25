import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate

    init() {
        ScreenshotLocalization.applyIfNeeded()
        TailscaleSSHTerminalRegistration.registerIfAvailable()
    }

    var body: some Scene {
        MacApplication()
    }
}
