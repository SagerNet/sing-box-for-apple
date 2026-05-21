import Libbox
import Library
import SwiftUI

@MainActor
public struct TailscaleExitNodePickerView: View {
    @ObservedObject var viewModel: TailscaleStatusViewModel
    let endpointTag: String

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: TailscaleStatusViewModel, endpointTag: String) {
        self.viewModel = viewModel
        self.endpointTag = endpointTag
    }

    private var endpoint: TailscaleEndpointData? {
        viewModel.endpoint(tag: endpointTag)
    }

    private var candidates: [(group: TailscaleUserGroupData, peer: TailscalePeerData)] {
        guard let endpoint else { return [] }
        let selfStableID = endpoint.selfPeer?.stableID
        var rows: [(TailscaleUserGroupData, TailscalePeerData)] = []
        for group in endpoint.userGroups {
            for peer in group.peers where peer.exitNodeOption && peer.stableID != selfStableID {
                if searchText.isEmpty || peer.hostName.localizedCaseInsensitiveContains(searchText) {
                    rows.append((group, peer))
                }
            }
        }
        return rows
    }

    public var body: some View {
        List {
            Button {
                select(stableID: "")
            } label: {
                HStack {
                    Text("Disabled")
                        .foregroundStyle(.foreground)
                    Spacer()
                    if endpoint?.exitNode == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif

            ForEach(Array(candidates.enumerated()), id: \.offset) { _, row in
                Button {
                    select(stableID: row.peer.stableID)
                } label: {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(row.peer.online ? .green : Color(.systemGray))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.peer.hostName)
                                .foregroundStyle(.foreground)
                                .lineLimit(1)
                            if let firstIP = row.peer.tailscaleIPs.first {
                                Text(firstIP)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if endpoint?.exitNode?.stableID == row.peer.stableID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        #else
        .searchable(text: $searchText)
        #endif
        .navigationTitle("Exit Node")
    }

    private func select(stableID: String) {
        Task {
            await viewModel.setExitNode(endpointTag: endpointTag, stableID: stableID)
            dismiss()
        }
    }
}
