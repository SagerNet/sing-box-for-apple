import Library
import MacLibrary
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor private var appDelegate: IndependentApplicationDelegate

    var body: some Scene {
        MacApplication()
    }
}
