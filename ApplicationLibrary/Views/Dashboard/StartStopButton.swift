import Library
import NetworkExtension
import SwiftUI

@MainActor
public struct StartStopButton: View {
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init() {}

    public var body: some View {
        viewBuilder {
            if ApplicationLibrary.inPreview {
                Button {} label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .labelStyle(.iconOnly)
            } else if let profile = environments.extensionProfile {
                Button0().environmentObject(profile)
            } else {
                Button {} label: {
                    Label("Start", systemImage: "play.fill")
                }
                .labelStyle(.iconOnly)
                .disabled(true)
            }
        }
        .disabled(environments.emptyProfiles)
    }

    private struct Button0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?

        var body: some View {
            Button {
                Task {
                    await switchProfile(!profile.status.isConnected)
                }
            } label: {
                if !profile.status.isConnected {
                    Label("Start", systemImage: "play.fill")
                } else {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            .labelStyle(.iconOnly)
            .disabled(!profile.status.isEnabled)
            .alertBinding($alert)
        }

        private nonisolated func switchProfile(_ isEnabled: Bool) async {
            do {
                if isEnabled {
                    try await profile.start()
                    await environments.commandClient.connect()
                } else {
                    try await profile.stop()
                }
            } catch {
                await MainActor.run {
                    alert = Alert(error)
                }
            }
        }
    }
}
