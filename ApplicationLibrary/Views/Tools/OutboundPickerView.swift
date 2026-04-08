import Libbox
import Library
import SwiftUI

@MainActor
public protocol OutboundSelectable: ObservableObject {
    var selectedOutbound: String { get set }
    var isRunning: Bool { get }
    func cancel()
}

public struct ToolOutboundSection<VM: OutboundSelectable>: View {
    @ObservedObject var profile: ExtensionProfile
    @ObservedObject var viewModel: VM

    public var body: some View {
        Group {
            if profile.status.isConnectedStrict {
                FormNavigationLink {
                    OutboundPickerView(selectedOutbound: $viewModel.selectedOutbound)
                } label: {
                    HStack {
                        Text("Outbound")
                        Spacer()
                        Text(viewModel.selectedOutbound.isEmpty ? String(localized: "Default") : viewModel.selectedOutbound)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .onChangeCompat(of: profile.status) { status in
            if !status.isConnectedStrict {
                if viewModel.isRunning {
                    viewModel.cancel()
                }
                viewModel.selectedOutbound = ""
            }
        }
    }
}

@MainActor
public struct OutboundPickerView: View {
    @Binding var selectedOutbound: String
    @StateObject private var commandClient = CommandClient(.outbounds)
    @State private var outbounds: [OutboundGroupItem] = []
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredOutbounds: [OutboundGroupItem] {
        if searchText.isEmpty {
            return outbounds
        }
        return outbounds.filter { $0.tag.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        List {
            Button {
                selectedOutbound = ""
                dismiss()
            } label: {
                HStack {
                    Text("Default")
                        .foregroundStyle(.foreground)
                    Spacer()
                    if selectedOutbound.isEmpty {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #endif
            ForEach(filteredOutbounds, id: \.tag) { item in
                Button {
                    selectedOutbound = item.tag
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.tag)
                                .foregroundStyle(.foreground)
                                .lineLimit(1)
                            HStack {
                                Text(item.displayType)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 0)
                                if item.urlTestDelay > 0 {
                                    Text(item.delayString)
                                        .font(.caption)
                                        .foregroundColor(item.delayColor)
                                }
                            }
                        }
                        if selectedOutbound == item.tag {
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
        .navigationTitle("Outbound")
        .onAppear {
            commandClient.connect()
        }
        .onDisappear {
            commandClient.disconnect()
        }
        .onReceive(commandClient.$outbounds) { goOutbounds in
            guard let goOutbounds else { return }
            outbounds = goOutbounds.map { OutboundGroupItem($0) }
        }
    }
}
