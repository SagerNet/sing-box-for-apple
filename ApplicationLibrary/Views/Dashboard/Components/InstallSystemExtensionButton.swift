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
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        alert = AlertState(errorMessage: String(localized: "Need Reboot"))
                    }
                }
                await callback()
            } catch {
                alert = AlertState(error: error)
            }
        }
    }

#endif
