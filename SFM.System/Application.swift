import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate

    init() {
        Variant.useSystemExtension = true
    }

    var body: some Scene {
        MacApplication()
    }
}
