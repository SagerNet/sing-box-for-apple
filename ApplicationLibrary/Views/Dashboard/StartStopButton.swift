import Library
import NetworkExtension
import SwiftUI

public struct StartStopButton: View {
    @EnvironmentObject private var environments: ExtensionEnvironments

    public init() {}

    public var body: some View {
        viewBuilder {
            if ApplicationLibrary.inPreview {
                #if os(iOS) || os(tvOS)
                    Toggle(isOn: .constant(true)) {
                        Text("Enabled")
                    }
                #elseif os(macOS)
                    Button(action: {}, label: {
                        Label("Stop", systemImage: "stop.fill")
                    })
                #endif

            } else if let profile = environments.extensionProfile {
                Button0().environmentObject(profile)
            } else {
                #if os(iOS) || os(tvOS)
                    Toggle(isOn: .constant(false)) {
                        Text("Enabled")
                    }
                #elseif os(macOS)

                    Button(action: {}, label: {
                        Label("Start", systemImage: "play.fill")
                    })
                    .disabled(true)
                #endif
            }
        }
    }

    private struct Button0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?

        var body: some View {
            viewBuilder {
                #if os(iOS) || os(tvOS)
                    Toggle(isOn: Binding(get: {
                        profile.status.isConnected
                    }, set: { newValue, _ in
                        Task.detached {
                            await switchProfile(newValue)
                        }
                    })) {
                        Text("Enabled")
                    }
                #elseif os(macOS)
                    Button(action: {
                        Task.detached {
                            await switchProfile(!profile.status.isConnected)
                        }
                    }, label: {
                        if !profile.status.isConnected {
                            Label("Start", systemImage: "play.fill")
                        } else {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    })
                #endif
            }
            .disabled(!profile.status.isEnabled)
            .alertBinding($alert)
        }

        private func switchProfile(_ isEnabled: Bool) async {
            do {
                if isEnabled {
                    try await profile.start()
                    environments.logClient.connect()
                } else {
                    profile.stop()
                }
            } catch {
                alert = Alert(error)
                return
            }
        }
    }
}
