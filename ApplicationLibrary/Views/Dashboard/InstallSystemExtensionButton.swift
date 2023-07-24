#if os(macOS)

    import Library
    import SwiftUI

    public struct InstallSystemExtensionButton: View {
        @State private var errorPresented = false
        @State private var errorMessage = ""
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
            .alert(isPresented: $errorPresented) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }

        private func installSystemExtension() async {
            do {
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        errorMessage = "Need reboot"
                        errorPresented = true
                    }
                }
                callback()
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
            }
        }
    }

#endif
