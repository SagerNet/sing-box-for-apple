import AppKit
import ApplicationLibrary
import Foundation
import Libbox
import Library
import UserNotifications

open class ApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public func applicationDidFinishLaunching(_: Notification) {
        NSLog("Here I stand")
        LibboxSetup(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, false)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.setNotificationCategories([
            UNNotificationCategory(
                identifier: "OPEN_URL",
                actions: [
                    UNNotificationAction(identifier: "COPY_URL", title: "Copy URL", options: .foreground, icon: UNNotificationActionIcon(systemImageName: "clipboard.fill")),
                    UNNotificationAction(identifier: "OPEN_URL", title: "Open", options: .foreground, icon: UNNotificationActionIcon(systemImageName: "safari.fill")),
                ],
                intentIdentifiers: []
            ),
        ]
        )
        notificationCenter.delegate = self
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAsLogInItem =
            event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if SharedPreferences.inDebug || !launchedAsLogInItem || !SharedPreferences.showMenuBarExtra.getBlocking() || !SharedPreferences.menuBarExtraInBackground.getBlocking() {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.windows.first?.close()
        }
        Task {
            do {
                try await ProfileUpdateTask.configure()
                if launchedAsLogInItem {
                    if await SharedPreferences.startedByUser.get() {
                        if let profile = try await ExtensionProfile.load() {
                            try await profile.start()
                        }
                    }
                }
            } catch {
                NSLog("application setup error: \(error.localizedDescription)")
            }
        }
    }

    public func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        .banner
    }

    public func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let url = response.notification.request.content.userInfo["OPEN_URL"] as? String {
            switch response.actionIdentifier {
            case "COPY_URL":
                NSPasteboard.general.setString(url, forType: .URL)
            case "OPEN_URL":
                fallthrough
            default:
                NSWorkspace.shared.open(URL(string: url)!)
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        SharedPreferences.inDebug || !SharedPreferences.menuBarExtraInBackground.getBlocking()
    }

    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
        }
        return true
    }
}
