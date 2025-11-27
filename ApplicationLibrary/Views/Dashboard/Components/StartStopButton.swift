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
                    #if os(tvOS)
                        Image(systemName: "stop.fill")
                    #else
                        Label("Stop", systemImage: "stop.fill")
                    #endif
                }
                .labelStyle(.iconOnly)
            } else if let profile = environments.extensionProfile {
                ToggleConnectionButton().environmentObject(profile)
            } else {
                Button {} label: {
                    #if os(tvOS)
                        Image(systemName: "play.fill")
                    #else
                        Label("Start", systemImage: "play.fill")
                    #endif
                }
                .labelStyle(.iconOnly)
                .disabled(true)
            }
        }
        .disabled(environments.emptyProfiles)
    }

    private struct ToggleConnectionButton: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?
        @State private var currentTime = Date()

        private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        var body: some View {
            Button {
                Task {
                    await switchProfile(!profile.status.isConnected)
                }
            } label: {
                #if os(iOS)
                    HStack(spacing: 8) {
                        if showRuntimeDuration, profile.status.isConnectedStrict, let duration = runtimeDuration {
                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }

                        if !profile.status.isConnected {
                            Label("Start", systemImage: "play.fill")
                        } else {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: profile.status.isConnectedStrict)
                #elseif os(tvOS)
                    if !profile.status.isConnected {
                        Image(systemName: "play.fill")
                    } else {
                        Image(systemName: "stop.fill")
                    }
                #else
                    HStack(spacing: 8) {
                        if profile.status.isConnectedStrict, let duration = runtimeDuration {
                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }

                        if !profile.status.isConnected {
                            Label("Start", systemImage: "play.fill")
                        } else {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: profile.status.isConnectedStrict)
                #endif
            }
            .labelStyle(.iconOnly)
            #if os(iOS)
                .modifier(PrimaryTintModifier())
            #endif
                .disabled(!profile.status.isEnabled)
                .alertBinding($alert)
                .onReceive(timer) { _ in
                    currentTime = Date()
                }
        }

        #if os(iOS)
            private var showRuntimeDuration: Bool {
                if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                    return true
                }
                return false
            }
        #endif

        private var runtimeDuration: String? {
            guard let connectedDate = profile.connectedDate else { return nil }
            let interval = currentTime.timeIntervalSince(connectedDate)
            guard interval >= 0 else { return nil }

            let hours = Int(interval) / 3600
            let minutes = Int(interval) / 60 % 60
            let seconds = Int(interval) % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
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

#if os(iOS)
    private struct PrimaryTintModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *), !Variant.debugNoIOS26 {
                content.tint(.primary)
            } else {
                content
            }
        }
    }
#endif
