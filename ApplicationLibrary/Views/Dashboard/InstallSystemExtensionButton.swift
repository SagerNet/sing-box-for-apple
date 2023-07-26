#if os(macOS)

    import Library
    import SwiftUI

    public struct InstallSystemExtensionButton: View {
        @State private var alert: Alert?
        private let callback: () -> Void
        public init(_ callback: @escaping () -> Void) {
            self.callback = callback
        }

        public var body: some View {
            Button("Install SystemExtension") {
                Task {
                    await installSystemExtension()
                }
            }
            .alertBinding($alert)
        }

        private func installSystemExtension() async {
            do {
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        alert = Alert(errorMessage: "Need Reboot")
                    }
                }
                callback()
            } catch {
                alert = Alert(error)
            }
        }
    }

#endif
