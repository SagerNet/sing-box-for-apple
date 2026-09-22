import Library
import SwiftUI

@MainActor
public struct RuntimeDurationText: View {
    @ObservedObject private var profile: ExtensionProfile
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(profile: ExtensionProfile) {
        _profile = ObservedObject(wrappedValue: profile)
    }

    public var body: some View {
        Group {
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
        }
        .onReceive(timer) { _ in
            guard !Variant.screenshotMode else { return }
            Task { @MainActor in
                currentTime = Date()
            }
        }
    }

    private var runtimeDuration: String? {
        guard let connectedDate = profile.connectedDate else { return nil }
        let interval: TimeInterval
        if Variant.screenshotMode {
            interval = 3600
        } else {
            interval = currentTime.timeIntervalSince(connectedDate)
        }
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
}
