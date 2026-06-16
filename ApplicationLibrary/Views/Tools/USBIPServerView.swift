import Library
import SwiftUI

@MainActor
public struct USBIPServerView: View {
    @ObservedObject var viewModel: USBIPStatusViewModel
    #if os(macOS)
        @EnvironmentObject private var providerViewModel: USBIPProviderViewModel
        @State private var detailDevice: USBSharedDeviceData?
    #endif
    @Environment(\.dismiss) private var dismiss
    let serverTag: String

    public init(viewModel: USBIPStatusViewModel, serverTag: String) {
        self.viewModel = viewModel
        self.serverTag = serverTag
    }

    private var server: USBIPServerData? {
        viewModel.server(tag: serverTag)
    }

    private var navigationTitleKey: LocalizedStringKey {
        viewModel.servers.count > 1 ? "USB/IP: \(serverTag)" : "USB/IP"
    }

    public var body: some View {
        FormView {
            if let server {
                Section {
                    deviceSection(server)
                } header: {
                    Text("Devices")
                } footer: {
                    providerFooter
                }
            }
        }
        .navigationTitle(navigationTitleKey)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addDeviceMenu
            }
        }
        .alert($providerViewModel.alert)
        .onAppear {
            providerViewModel.reloadLocalDevices()
        }
        .background {
            NavigationDestinationCompat(isPresented: detailActive) {
                if let detailDevice {
                    USBIPDeviceView(device: detailDevice)
                }
            }
        }
        #endif
        .onChangeCompat(of: server == nil) { isNil in
            if isNil {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func deviceSection(_ server: USBIPServerData) -> some View {
        #if os(macOS)
            let pending = pendingLocalDevices(visibleDevices: server.devices)
            if server.devices.isEmpty, pending.isEmpty {
                Text("No devices shared yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(server.devices) { device in
                    deviceLink(device)
                }
                ForEach(pending) { device in
                    pendingDeviceRow(device)
                }
            }
        #else
            if server.devices.isEmpty {
                Text("No devices shared yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(server.devices) { device in
                    deviceLink(device)
                }
            }
        #endif
    }

    private func deviceLink(_ device: USBSharedDeviceData) -> some View {
        let state = usbDeviceState(device.state)
        let label = deviceRowLabel(name: device.displayName, dotColor: state.color, stateLabel: state.label)
        #if os(macOS)
            let isProvided = providerViewModel.providedDevice(serverTag: serverTag, deviceID: device.deviceID) != nil
            return DeviceRow(
                label: label,
                onOpen: { detailDevice = device },
                onDetach: isProvided ? { providerViewModel.detach(deviceID: device.deviceID) } : nil
            )
        #else
            return FormNavigationLink {
                USBIPDeviceView(device: device)
            } label: {
                label
            }
        #endif
    }

    private func deviceRowLabel(name: String, dotColor: some ShapeStyle, stateLabel: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(dotColor)
            Text(verbatim: "\(name):")
                .lineLimit(1)
                .truncationMode(.tail)
            Text(stateLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
    }

    #if os(macOS)
        private var addDeviceMenu: some View {
            let devices = providerViewModel.attachableDevices()
            return Menu {
                if devices.isEmpty {
                    Text("No local devices available")
                } else {
                    ForEach(devices) { device in
                        Button {
                            providerViewModel.attach(serverTag: serverTag, localDeviceID: device.id)
                        } label: {
                            Text(verbatim: attachMenuLabel(device))
                        }
                    }
                }
            } label: {
                Label("Share USB Device", systemImage: "plus")
            }
            .disabled(!providerViewModel.isStarted)
        }

        private func attachMenuLabel(_ device: USBLocalDeviceData) -> String {
            if device.product.isEmpty {
                return device.displayName
            }
            return "\(device.product) (\(usbFormatVidPid(device.vendorID, device.productID)))"
        }

        private var detailActive: Binding<Bool> {
            Binding(
                get: { detailDevice != nil },
                set: { active in
                    if !active {
                        detailDevice = nil
                    }
                }
            )
        }

        private struct DeviceRow<Label: View>: View {
            let label: Label
            let onOpen: (() -> Void)?
            let onDetach: (() -> Void)?
            @State private var isHovered = false

            var body: some View {
                HStack(spacing: 8) {
                    if let onOpen {
                        Button(action: onOpen) {
                            label
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        label
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let onDetach {
                        Button(role: .destructive, action: onDetach) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop Sharing")
                    }
                }
                .onHover { hovering in
                    isHovered = hovering
                }
                .listRowBackground(isHovered ? Color.primary.opacity(0.07) : nil)
            }
        }

        private var providerFooter: some View {
            Text("Use the + button to share a local USB device from this Mac.")
        }

        private func pendingLocalDevices(visibleDevices: [USBSharedDeviceData]) -> [USBLocalProvidedDeviceData] {
            providerViewModel.pendingDevices(
                serverTag: serverTag,
                visibleDeviceIDs: Set(visibleDevices.map(\.deviceID))
            )
        }

        private func pendingDeviceRow(_ device: USBLocalProvidedDeviceData) -> some View {
            DeviceRow(
                label: deviceRowLabel(name: device.displayName, dotColor: .secondary, stateLabel: "Preparing"),
                onOpen: nil,
                onDetach: { providerViewModel.detach(deviceID: device.deviceID) }
            )
        }
    #else
        private var providerFooter: some View {
            Text("To provide devices, use a Chromium-based browser with the sing-box dashboard, or the sing-box graphical client on macOS or Android.")
        }
    #endif
}
