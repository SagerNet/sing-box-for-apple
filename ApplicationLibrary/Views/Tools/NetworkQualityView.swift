import Libbox
import Library
import SwiftUI

@MainActor
public struct NetworkQualityView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = NetworkQualityViewModel()

    public init() {}

    private var downloadActive: Bool {
        (viewModel.isRunning && !viewModel.serial && viewModel.phase >= LibboxNetworkQualityPhaseDownload && viewModel.phase < LibboxNetworkQualityPhaseDone)
            || viewModel.phase == LibboxNetworkQualityPhaseDownload
    }

    private func accuracyLabel(_ value: Int32) -> (label: String, color: Color) {
        switch value {
        case LibboxNetworkQualityAccuracyHigh:
            return (String(localized: "Confidence High"), .green)
        case LibboxNetworkQualityAccuracyMedium:
            return (String(localized: "Confidence Medium"), .yellow)
        default:
            return (String(localized: "Confidence Low"), .red)
        }
    }

    private var uploadActive: Bool {
        (viewModel.isRunning && !viewModel.serial && viewModel.phase >= LibboxNetworkQualityPhaseDownload && viewModel.phase < LibboxNetworkQualityPhaseDone)
            || viewModel.phase == LibboxNetworkQualityPhaseUpload
    }

    @ViewBuilder
    private func resultValue(_ value: String?, active: Bool, accuracy: (label: String, color: Color)? = nil) -> some View {
        if let value {
            HStack(spacing: 6) {
                if viewModel.isRunning, active {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(value)
                if let accuracy {
                    Text(accuracy.label)
                        .font(.caption)
                        .foregroundColor(accuracy.color)
                }
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
                    FormTextItem("URL", "link") {
                        Text(viewModel.configURL)
                    }
                #else
                    FormItem("URL") {
                        TextField(text: $viewModel.configURL) {}
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                    }
                #endif
                Toggle("Serial", isOn: $viewModel.serial)
                    .disabled(viewModel.isRunning)
                Toggle("HTTP/3", isOn: $viewModel.http3)
                    .disabled(viewModel.isRunning)
                Picker("Max Runtime", selection: $viewModel.maxRuntime) {
                    ForEach(MaxRuntimeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .disabled(viewModel.isRunning)
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
                        viewModel.requestStartTest(vpnConnected: environments.extensionProfile?.status.isConnectedStrict == true)
                    } label: {
                        Label("Start Test", systemImage: "play.fill")
                    }
                }
            }

            if viewModel.phase >= 0 {
                Section("Results") {
                    FormTextItem("Idle Latency", "timer") {
                        resultValue(viewModel.idleLatencyMs > 0 ? "\(viewModel.idleLatencyMs) ms" : nil, active: viewModel.phase == LibboxNetworkQualityPhaseIdle)
                    }
                    FormTextItem("Download", "arrow.down.circle") {
                        resultValue(viewModel.downloadCapacity > 0 ? LibboxFormatBitrate(viewModel.downloadCapacity) : nil, active: downloadActive, accuracy: viewModel.phase == LibboxNetworkQualityPhaseDone ? accuracyLabel(viewModel.downloadCapacityAccuracy) : nil)
                    }
                    FormTextItem("Download RPM", "arrow.down.to.line") {
                        resultValue(viewModel.downloadRPM > 0 ? "\(viewModel.downloadRPM)" : nil, active: downloadActive, accuracy: viewModel.phase == LibboxNetworkQualityPhaseDone ? accuracyLabel(viewModel.downloadRPMAccuracy) : nil)
                    }
                    FormTextItem("Upload", "arrow.up.circle") {
                        resultValue(viewModel.uploadCapacity > 0 ? LibboxFormatBitrate(viewModel.uploadCapacity) : nil, active: uploadActive, accuracy: viewModel.phase == LibboxNetworkQualityPhaseDone ? accuracyLabel(viewModel.uploadCapacityAccuracy) : nil)
                    }
                    FormTextItem("Upload RPM", "arrow.up.to.line") {
                        resultValue(viewModel.uploadRPM > 0 ? "\(viewModel.uploadRPM)" : nil, active: uploadActive, accuracy: viewModel.phase == LibboxNetworkQualityPhaseDone ? accuracyLabel(viewModel.uploadRPMAccuracy) : nil)
                    }
                }
            }
        }
        .navigationTitle("Network Quality")
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
