import Foundation
import Libbox
import Library

#if os(macOS)
    public struct USBLocalDeviceData: Identifiable {
        public var id: String {
            stableID
        }

        public let stableID: String
        public let busID: String
        public let backend: Int32
        public let busNum: Int32
        public let devNum: Int32
        public let speed: Int32
        public let vendorID: Int32
        public let productID: Int32
        public let bcdDevice: Int32
        public let deviceClass: Int32
        public let deviceSubClass: Int32
        public let deviceProtocol: Int32
        public let configurationValue: Int32
        public let numConfigurations: Int32
        public let serial: String
        public let product: String
        public let interfaces: [USBInterfaceData]

        public var displayName: String {
            if !product.isEmpty {
                return product
            }
            if vendorID != 0 || productID != 0 {
                return usbFormatVidPid(vendorID, productID)
            }
            return busID.isEmpty ? stableID : busID
        }
    }

    public struct USBLocalProvidedDeviceData: Identifiable {
        public let id: String
        public let serverTag: String
        public let deviceID: String
        public let localDeviceID: String
        public let label: String
        public let vendorID: Int32
        public let productID: Int32

        public var displayName: String {
            if !label.isEmpty {
                return label
            }
            if vendorID != 0 || productID != 0 {
                return usbFormatVidPid(vendorID, productID)
            }
            return deviceID
        }
    }

    @MainActor
    public final class USBIPProviderViewModel: BaseViewModel {
        @Published public var localDevices: [USBLocalDeviceData] = []
        @Published public var providedDevices: [USBLocalProvidedDeviceData] = []
        @Published public var isStarted = false

        private var manager: LibboxUSBLocalProviderManager?
        private var handler: ProviderHandler?

        deinit {
            try? manager?.close()
        }

        public func start() {
            guard manager == nil else {
                reloadLocalDevices()
                return
            }
            let handler = ProviderHandler(self)
            self.handler = handler
            Task { [weak self] in
                do {
                    let manager = try await Task.detached {
                        try CommandTarget.standaloneClient().newUSBLocalProvider(handler)
                    }.value
                    guard let self else {
                        try? manager.close()
                        return
                    }
                    self.manager = manager
                    self.isStarted = true
                    self.reloadLocalDevices()
                } catch {
                    guard let self else { return }
                    self.handler = nil
                    self.manager = nil
                    self.isStarted = false
                    self.localDevices = []
                    self.showError(error, action: "start USB/IP provider")
                }
            }
        }

        public func cancel() {
            try? manager?.close()
            manager = nil
            handler = nil
            isStarted = false
            localDevices = []
            providedDevices = []
        }

        public func reloadLocalDevices() {
            guard let manager else {
                localDevices = []
                return
            }
            Task { [weak self, manager] in
                do {
                    let devices = try await Task.detached {
                        try Self.convertLocalDevices(manager.listDevices())
                    }.value
                    guard let self else { return }
                    self.localDevices = devices
                } catch {
                    guard let self else { return }
                    self.showError(error, action: "list local USB devices")
                }
            }
        }

        public func attach(serverTag: String, localDeviceID: String) {
            guard let manager else {
                return
            }
            Task { [weak self, manager] in
                do {
                    let provided = try await Task.detached {
                        try manager.attach(serverTag, localDeviceID: localDeviceID)
                    }.value
                    let data = Self.convertProvidedDevice(provided)
                    guard let self else { return }
                    self.upsertProvidedDevice(data)
                } catch {
                    guard let self else { return }
                    self.showError(error, action: "share USB device")
                }
            }
        }

        public func detach(deviceID: String) {
            guard let manager else {
                return
            }
            Task { [weak self, manager] in
                do {
                    try await Task.detached {
                        try manager.detach(deviceID)
                    }.value
                    guard let self else { return }
                    self.providedDevices.removeAll { $0.deviceID == deviceID }
                } catch {
                    guard let self else { return }
                    self.showError(error, action: "stop sharing USB device")
                }
            }
        }

        public func providedDevice(serverTag: String, deviceID: String) -> USBLocalProvidedDeviceData? {
            providedDevices.first { $0.serverTag == serverTag && $0.deviceID == deviceID }
        }

        public func pendingDevices(serverTag: String, visibleDeviceIDs: Set<String>) -> [USBLocalProvidedDeviceData] {
            providedDevices.filter { $0.serverTag == serverTag && !visibleDeviceIDs.contains($0.deviceID) }
        }

        public func attachableDevices() -> [USBLocalDeviceData] {
            let attached = Set(providedDevices.map(\.localDeviceID))
            return localDevices.filter { !attached.contains($0.stableID) }
        }

        private func upsertProvidedDevice(_ device: USBLocalProvidedDeviceData) {
            if let index = providedDevices.firstIndex(where: { $0.deviceID == device.deviceID }) {
                providedDevices[index] = device
            } else {
                providedDevices.append(device)
            }
        }

        private nonisolated static func convertLocalDevices(_ iterator: (any LibboxUSBLocalDeviceInfoIteratorProtocol)?) -> [USBLocalDeviceData] {
            var devices: [USBLocalDeviceData] = []
            guard let iterator else { return devices }
            while iterator.hasNext() {
                if let device = iterator.next() {
                    devices.append(convertLocalDevice(device))
                }
            }
            return devices
        }

        private nonisolated static func convertLocalDevice(_ device: LibboxUSBLocalDeviceInfo) -> USBLocalDeviceData {
            let interfaces = device.interfaces()?.toInterfaceDataArray() ?? []
            return USBLocalDeviceData(
                stableID: device.stableID,
                busID: device.busID,
                backend: device.backend,
                busNum: device.busNum,
                devNum: device.devNum,
                speed: device.speed,
                vendorID: device.vendorID,
                productID: device.productID,
                bcdDevice: device.bcdDevice,
                deviceClass: device.deviceClass,
                deviceSubClass: device.deviceSubClass,
                deviceProtocol: device.deviceProtocol,
                configurationValue: device.configurationValue,
                numConfigurations: device.numConfigurations,
                serial: device.serial,
                product: device.product,
                interfaces: interfaces
            )
        }

        private nonisolated static func convertProvidedDevice(_ device: LibboxUSBLocalProvidedDevice) -> USBLocalProvidedDeviceData {
            USBLocalProvidedDeviceData(
                id: device.deviceID,
                serverTag: device.serverTag,
                deviceID: device.deviceID,
                localDeviceID: device.localDeviceID,
                label: device.label,
                vendorID: device.vendorID,
                productID: device.productID
            )
        }

        private final class ProviderHandler: NSObject, LibboxUSBLocalProviderHandlerProtocol, @unchecked Sendable {
            private weak var viewModel: USBIPProviderViewModel?

            init(_ viewModel: USBIPProviderViewModel?) {
                self.viewModel = viewModel
            }

            func onDeviceError(_ serverTag: String?, deviceID: String?, message _: String?) {
                DispatchQueue.main.async { [self] in
                    guard let viewModel, let deviceID else { return }
                    viewModel.providedDevices.removeAll {
                        $0.deviceID == deviceID && (serverTag == nil || $0.serverTag == serverTag)
                    }
                }
            }

            func onSessionError(_ serverTag: String?, message _: String?) {
                DispatchQueue.main.async { [self] in
                    guard let viewModel else { return }
                    if let serverTag, !serverTag.isEmpty {
                        viewModel.providedDevices.removeAll { $0.serverTag == serverTag }
                    } else {
                        viewModel.providedDevices = []
                    }
                }
            }

            func onLocalDevicesChanged() {
                DispatchQueue.main.async { [self] in
                    viewModel?.reloadLocalDevices()
                }
            }
        }
    }
#endif
