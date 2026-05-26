import ApplicationLibrary
import Foundation
import Library
import SwiftUI

@main
struct Application: App {
    @UIApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate
    @StateObject private var environments = ExtensionEnvironments()
    @StateObject private var peerStore = TailscaleSSHPeerStore()

    init() {
        Task { @MainActor in
            ImportedFontStore.shared.bootstrap()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(environments)
                .environmentObject(peerStore)
        }
    }
}
