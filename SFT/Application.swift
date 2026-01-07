import Foundation
import Library
import SwiftUI

@main
struct Application: App {
    @UIApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate
    @StateObject private var environments = ExtensionEnvironments()

    init() {
        ScreenshotLocalization.applyIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(environments)
        }
    }
}
