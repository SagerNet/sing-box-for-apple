import Library
import SwiftUI

@MainActor
public struct InstallProfileButton: View {
    @State private var alert: Alert?

    private let callback: () async -> Void
    public init(_ callback: @escaping (() async -> Void)) {
        self.callback = callback
    }

    public var body: some View {
        FormButton {
            Task {
                await installProfile()
            }
        } label: {
            Label("Install Network Extension", systemImage: "lock.doc.fill")
        }
        .alertBinding($alert)
    }

    private func installProfile() async {
        do {
            try await ExtensionProfile.install()
            await callback()
        } catch {
            alert = Alert(error)
        }
    }
}
