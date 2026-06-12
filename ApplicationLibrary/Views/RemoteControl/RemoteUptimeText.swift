#if os(iOS) || os(macOS)
    import Library
    import SwiftUI

    /// Shows the remote service uptime, mirroring the runtime duration the
    /// local service displays next to the stop button.
    public struct RemoteUptimeText: View {
        @ObservedObject private var commandClient: CommandClient
        @State private var startedAt: Date?
        @State private var currentTime = Date()

        private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        public init(commandClient: CommandClient) {
            _commandClient = ObservedObject(wrappedValue: commandClient)
        }

        public var body: some View {
            // ZStack rather than Group: modifiers on a Group distribute to its
            // children, and while uptime is nil there are no children, so
            // onAppear/onChange would never fire and startedAt would never load.
            ZStack {
                if let uptime {
                    Text(uptime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .onAppear {
                if commandClient.isConnected {
                    fetchStartedAt()
                }
            }
            .onChangeCompat(of: commandClient.isConnected) { isConnected in
                if isConnected {
                    fetchStartedAt()
                } else {
                    startedAt = nil
                }
            }
            .onReceive(timer) { _ in
                guard startedAt != nil else { return }
                currentTime = Date()
            }
        }

        private var uptime: String? {
            guard commandClient.isConnected, let startedAt else { return nil }
            let interval = currentTime.timeIntervalSince(startedAt)
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

        private func fetchStartedAt() {
            Task.detached {
                guard let client = try? CommandTarget.standaloneClient() else { return }
                var value: Int64 = 0
                try? client.getStartedAt(&value)
                guard value > 0 else { return }
                let date = Date(timeIntervalSince1970: Double(value) / 1000)
                await MainActor.run {
                    startedAt = date
                    currentTime = Date()
                }
            }
        }
    }
#endif
