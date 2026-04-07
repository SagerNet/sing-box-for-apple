import ApplicationLibrary
import Foundation
import Libbox
import Library
import UIKit

class ApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NativeCrashReporter.installForCurrentProcess()
        NSLog("Here I stand")
        let options = LibboxSetupOptions()
        options.basePath = FilePath.sharedDirectory.relativePath
        options.workingPath = FilePath.workingDirectory.relativePath
        options.tempPath = FilePath.cacheDirectory.relativePath
        var port = SharedPreferences.commandServerPort.getBlocking()
        var secret = SharedPreferences.commandServerSecret.getBlocking()
        if port == 0 || secret.isEmpty {
            var error: NSError?
            LibboxAvailablePort(7990, &port, &error)
            if let error {
                port = 7990
                NSLog("Failed to get available port for control server: \(error.localizedDescription)")
            }
            secret = LibboxRandomHex(16)!.value
            Task {
                await SharedPreferences.commandServerPort.set(port)
                await SharedPreferences.commandServerSecret.set(secret)
            }
        }
        options.commandServerListenPort = port
        options.commandServerSecret = secret
        options.crashReportSource = "Application"
        var error: NSError?
        LibboxSetup(options, &error)
        if let error {
            NSLog("setup service error: \(error.localizedDescription)")
        }
        var localeError: NSError?
        LibboxSetLocale(Locale.current.identifier, &localeError)
        if let localeError {
            NSLog("failed to set locale: \(localeError)")
        }
        setup()
        return true
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
