import AppKit
import Foundation
import Libbox
import Library
import MacLibrary

class StandaloneApplicationDelegate: ApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        Variant.useSystemExtension = true
        Variant.isBeta = false
        LibboxSetXPCDialer(CommandXPCDialer.shared)
        UserServiceEndpointPublisher.shared.start()
        Task {
            await setupSystemExtension()
            await HelperServiceManager.updateRootHelperIfNeeded()
        }
    }

    private nonisolated func setupSystemExtension() async {
        do {
            if await SystemExtension.isInstalled() {
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        return
                    }
                }
            }
        } catch {
            NSLog("setup system extension error: \(error.localizedDescription)")
        }
    }
}
