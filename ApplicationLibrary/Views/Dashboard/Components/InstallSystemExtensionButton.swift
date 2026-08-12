#if os(macOS)

    import Library
    import SwiftUI

    @MainActor
    public struct InstallSystemExtensionButton: View {
        @State private var alert: AlertState?
        private let callback: () async -> Void
        public init(_ callback: @escaping () async -> Void) {
            self.callback = callback
        }

        public var body: some View {
            FormButton {
                Task {
                    await installSystemExtension()
                }
            } label: {
                Label("Install System Extension", systemImage: "lock.doc.fill")
            }
            .alert($alert)
        }

        private func installSystemExtension() async {
            do {
                let result = try await SystemExtension.install()
                await SharedPreferences.rootHelperPromptPending.set(true)
                if result == .willCompleteAfterReboot {
                    alert = AlertState(errorMessage: String(localized: "Need Reboot"))
                } else {
                    NotificationCenter.default.post(name: .systemExtensionInstalled, object: nil)
                }
                await callback()
            } catch {
                alert = AlertState(action: "install system extension", error: error)
            }
        }
    }

#endif
