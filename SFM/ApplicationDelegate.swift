import AppKit
import ApplicationLibrary
import Foundation
import Libbox
import Library

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSLog("Here I stand")
        // ServiceNotification.register() // Not work
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAsLogInItem =
            event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAsLogInItem || !SharedPreferences.showMenuBarExtra || !SharedPreferences.menuBarExtraInBackground {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.windows.first?.close()
        }
        Task.detached {
            do {
                try await self.postStart(launchedAsLogInItem)
            } catch {
                NSLog("application setup error: \(error.localizedDescription)")
            }
        }
    }

    private func postStart(_ launchedAsLogInItem: Bool) async throws {
        try ProfileUpdateTask.setup()
        if launchedAsLogInItem {
            if SharedPreferences.startedByUser {
                if let profile = try await ExtensionProfile.load() {
                    try await profile.start()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        !SharedPreferences.menuBarExtraInBackground
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
        }
        return true
    }
}
