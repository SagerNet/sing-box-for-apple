import Library
import SwiftUI

public struct InstallProfileButton: View {
    @Environment(\.extensionProfile) private var extensionProfile

    @State private var errorPresented = false
    @State private var errorMessage = ""

    public init() {}

    public var body: some View {
        Button("Install NetworkExtension") {
            Task {
                await installProfile()
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

    private func installProfile() async {
        do {
            try await ExtensionProfile.install()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
        }
    }
}
