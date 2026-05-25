import SwiftUI

public struct TailscaleSSHUnavailableView: View {
    private let peerHostName: String
    @Environment(\.dismiss) private var dismiss

    public init(peerHostName: String) {
        self.peerHostName = peerHostName
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Terminal not available")
                .font(.headline)
            Text("Connect via SSH requires iOS 17 or macOS 14.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(peerHostName)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("OK") { dismiss() }
                }
            }
    }
}
