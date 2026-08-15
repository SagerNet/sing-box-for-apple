import ApplicationLibrary
import Foundation
import Library
import SwiftUI

@main
struct Application: App {
    @UIApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate
    @StateObject private var environments = ExtensionEnvironments()
    @StateObject private var peerStore = TailscaleSSHPeerStore()
    @StateObject private var tailscaleViewModel = TailscaleStatusViewModel()

    init() {
        ScreenshotLocalization.applyIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .tailscaleStatusSubscription(tailscaleViewModel, environments: environments, peerStore: peerStore)
                .environmentObject(environments)
                .environmentObject(peerStore)
                .environmentObject(tailscaleViewModel)
        }
    }
}
