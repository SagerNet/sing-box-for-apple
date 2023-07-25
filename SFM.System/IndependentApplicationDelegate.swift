import AppKit
import Foundation
import Library
import MacLibrary

class IndependentApplicationDelegate: ApplicationDelegate {
    public func applicationWillFinishLaunching(_: Notification) {
        Variant.useSystemExtension = true
        Task.detached {
            if await SystemExtension.isInstalled() {
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        return
                    }
                }
            }
        }
    }
}
