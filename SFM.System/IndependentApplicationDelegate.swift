import AppKit
import Foundation
import Library
import MacLibrary

class IndependentApplicationDelegate: ApplicationDelegate {
    public func applicationWillFinishLaunching(_: Notification) {
        Variant.useSystemExtension = true
        Task {
            await setupSystemExtension()
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
