import Libbox
import Library
import SwiftUI

@MainActor
public struct STUNTestView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = STUNTestViewModel()

    public init() {}

    private func natMappingColor(_ value: Int32) -> Color {
        switch value {
        case LibboxNATMappingEndpointIndependent: .green
        case LibboxNATMappingAddressDependent: .yellow
        case LibboxNATMappingAddressAndPortDependent: .red
        default: .primary
        }
    }

    private func natFilteringColor(_ value: Int32) -> Color {
        switch value {
        case LibboxNATFilteringEndpointIndependent: .green
        case LibboxNATFilteringAddressDependent: .yellow
        case LibboxNATFilteringAddressAndPortDependent: .red
        default: .primary
        }
    }

    @ViewBuilder
    private func resultValue(_ value: String?, active: Bool) -> some View {
        if let value {
            HStack(spacing: 6) {
                if viewModel.isRunning, active {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(value)
            }
        } else if viewModel.isRunning, active {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(verbatim: "-")
        }
    }

    public var body: some View {
        FormView {
            Section("Configuration") {
                #if os(tvOS)
                    FormTextItem("Server", "server.rack") {
                        Text(viewModel.server)
                    }
                #else
                    FormItem(String(localized: "Server")) {
                        TextField(text: $viewModel.server) {}
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                    }
                #endif
                if let profile = environments.extensionProfile {
                    ToolOutboundSection(profile: profile, viewModel: viewModel)
                }
            }

            Section("Action") {
                if viewModel.isRunning {
                    FormButton {
                        viewModel.cancel()
                    } label: {
                        Label("Cancel Test", systemImage: "stop.fill")
                    }
                } else {
                    FormButton {
                        viewModel.startTest(vpnConnected: environments.extensionProfile?.status.isConnectedStrict == true)
                    } label: {
                        Label("Start Test", systemImage: "play.fill")
                    }
                }
            }

            if viewModel.phase >= 0 {
                Section("Results") {
                    FormTextItem("External Address", "network") {
                        resultValue(viewModel.externalAddr.isEmpty ? nil : viewModel.externalAddr, active: viewModel.phase == LibboxSTUNPhaseBinding)
                    }
                    FormTextItem("Latency", "timer") {
                        resultValue(viewModel.latencyMs > 0 ? "\(viewModel.latencyMs) ms" : nil, active: viewModel.phase == LibboxSTUNPhaseBinding)
                    }
                    if viewModel.phase == LibboxSTUNPhaseDone, !viewModel.natTypeSupported {
                        FormTextItem("NAT Type Detection", "exclamationmark.triangle") {
                            Text("Not supported by server")
                        }
                    } else {
                        FormTextItem("NAT Mapping", "arrow.left.arrow.right") {
                            resultValue(viewModel.natMapping > 0 ? LibboxFormatNATMapping(viewModel.natMapping) : nil, active: viewModel.phase == LibboxSTUNPhaseNATMapping)
                                .foregroundStyle(viewModel.natMapping > 0 ? natMappingColor(viewModel.natMapping) : .primary)
                        }
                        FormTextItem("NAT Filtering", "line.3.horizontal.decrease") {
                            resultValue(viewModel.natFiltering > 0 ? LibboxFormatNATFiltering(viewModel.natFiltering) : nil, active: viewModel.phase == LibboxSTUNPhaseNATFiltering)
                                .foregroundStyle(viewModel.natFiltering > 0 ? natFilteringColor(viewModel.natFiltering) : .primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("STUN Test")
        .task {
            await viewModel.loadPreferences()
        }
        .alert($viewModel.alert)
        .onDisappear {
            if viewModel.isRunning {
                viewModel.cancel()
            }
        }
    }
}
