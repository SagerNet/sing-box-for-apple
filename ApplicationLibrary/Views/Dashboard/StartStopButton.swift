import Library
import NetworkExtension
import SwiftUI

public struct StartStopButton: View {
    @Environment(\.extensionProfile) private var extensionProfile

    public init() {}

    public var body: some View {
        viewBuilder {
            if ApplicationLibrary.inPreview {
                #if os(iOS)
                    Toggle(isOn: .constant(true)) {
                        Text("Enabled")
                    }
                #elseif os(macOS)
                    Button(action: {}, label: {
                        Label("Stop", systemImage: "stop.fill")
                    })
                #endif

            } else if let profile = extensionProfile.wrappedValue {
                Button0(profile)
            } else {
                #if os(iOS)
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
        @Environment(\.logClient) private var logClient
        @ObservedObject private var profile: ExtensionProfile
        @State private var errorPresented = false
        @State private var errorMessage = ""

        init(_ profile: ExtensionProfile) {
            self.profile = profile
        }

        var body: some View {
            viewBuilder {
                #if os(iOS)
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
            .alert(isPresented: $errorPresented) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok"))
                )
            }
        }

        private func switchProfile(_ isEnabled: Bool) async {
            do {
                if isEnabled {
                    try await profile.start()
                    logClient.wrappedValue?.reconnect()
                } else {
                    profile.stop()
                }
            } catch {
                errorMessage = error.localizedDescription
                errorPresented = true
                return
            }
        }
    }
}
