import Library
import SwiftUI

struct ShareView: View {
    @ObservedObject var viewModel: ShareViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Taildrop")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    if viewModel.isFinished {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                viewModel.onFinish?()
                            }
                        }
                    } else {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                viewModel.cancel()
                            }
                        }
                    }
                }
                .alert($viewModel.alert)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            centered {
                ProgressView()
            }
        } else if viewModel.isSending {
            List(viewModel.files) { file in
                VStack(alignment: .leading, spacing: 6) {
                    Text(file.name)
                        .lineLimit(1)
                    ProgressView(value: min(Double(file.sentBytes) / Double(max(file.size, 1)), 1))
                    Text(sentText(file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let unavailableMessage = viewModel.unavailableMessage {
            centered {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(unavailableMessage)
                    .multilineTextAlignment(.center)
                Button("Open sing-box") {
                    viewModel.openApplication()
                }
            }
        } else {
            List {
                Section("Files") {
                    ForEach(viewModel.files) { file in
                        HStack {
                            Text(file.name)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(viewModel.endpoints) { endpoint in
                    Section(sectionTitle(endpoint)) {
                        ForEach(endpoint.peers) { peer in
                            Button {
                                viewModel.send(endpointTag: endpoint.endpointTag, peer: peer)
                            } label: {
                                HStack {
                                    Text(peer.name)
                                    Spacer()
                                    if !peer.os.isEmpty {
                                        Text(peer.os)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func sentText(_ file: TaildropSendFile) -> String {
        let total = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        if file.completed {
            return total
        }
        let sent = ByteCountFormatter.string(fromByteCount: file.sentBytes, countStyle: .file)
        return sent + " / " + total
    }

    private func sectionTitle(_ endpoint: TaildropTargetEndpoint) -> String {
        if !endpoint.networkName.isEmpty {
            return endpoint.networkName
        }
        return endpoint.endpointTag
    }

    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 12) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
