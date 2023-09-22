import Library
import SwiftUI

@MainActor
public struct InstallProfileButton: View {
    @State private var alert: Alert?

    public init() {}

    public var body: some View {
        Button("Install NetworkExtension") {
            Task {
                await installProfile()
            }
        }
        .alertBinding($alert)
    }

    private func installProfile() async {
        do {
            try await ExtensionProfile.install()
        } catch {
            alert = Alert(error)
        }
    }
}
