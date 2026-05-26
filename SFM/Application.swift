import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate

    init() {
        ScreenshotLocalization.applyIfNeeded()
    }

    var body: some Scene {
        MacApplication()
    }
}
