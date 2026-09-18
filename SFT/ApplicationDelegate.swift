import ApplicationLibrary
import Foundation
import Libbox
import Library
import UIKit

@MainActor
class ApplicationDelegate: NSObject, UIApplicationDelegate {
    /// SwiftUI does not invalidate the App body when a delegate published through
    /// UIApplicationDelegateAdaptor sends objectWillChange, so readiness is awaited
    /// instead of observed.
    private(set) var setupTask: Task<Void, Never>?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        LibboxPrepareCrashSignalHandlers()
        NativeCrashReporter.installForCurrentProcess()
        LibboxReinstallCrashSignalHandlers()
        NSLog("Here I stand")
        setup()
        setupTask = Task {
            await setupService()
        }
        return true
    }

    private func setupService() async {
        let options = LibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath
        var port = await SharedPreferences.commandServerPort.get()
        var secret = await SharedPreferences.commandServerSecret.get()
        if port == 0 || secret.isEmpty {
            (port, secret) = await BlockingIO.run {
                var port: Int32 = 0
                var error: NSError?
                LibboxAvailablePort(7990, &port, &error)
                if let error {
                    port = 7990
                    NSLog("Failed to get available port for control server: \(error.localizedDescription)")
                }
                return (port, LibboxRandomHex(16)!.value)
            }
            await SharedPreferences.commandServerPort.set(port)
            await SharedPreferences.commandServerSecret.set(secret)
        }
        options.commandServerListenPort = port
        options.commandServerSecret = secret
        options.crashReportSource = "Application"
        options.appVersion = Bundle.application.versionNumber
        options.appMarketingVersion = Bundle.application.version
        await BlockingIO.run {
            var error: NSError?
            LibboxSetup(options, &error)
            if let error {
                NSLog("setup service error: \(error.localizedDescription)")
            }
            do {
                try ApplicationLocale.apply()
            } catch {
                NSLog("failed to set locale: \(error)")
            }
        }
    }

    private func setup() {
        do {
            try UIProfileUpdateTask.configure()
            NSLog("setup background task success")
        } catch {
            NSLog("setup background task error: \(error.localizedDescription)")
        }
    }
}
