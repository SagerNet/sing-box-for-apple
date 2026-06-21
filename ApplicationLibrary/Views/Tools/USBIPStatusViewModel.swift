import Foundation
import Libbox
import Library
import SwiftUI

public struct USBInterfaceData: Identifiable {
    public let id: Int
    public let interfaceClass: Int32
    public let interfaceSubClass: Int32
    public let interfaceProtocol: Int32
}

public struct USBSharedDeviceData: Identifiable {
    public let id: String
    public let busID: String
    public let stableID: String
    public let backend: Int32
    public let state: Int32
    public let deviceID: String
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
        return busID
    }
}

public struct USBIPServerData: Identifiable {
    public let id: String
    public let serverTag: String
    public let devices: [USBSharedDeviceData]
}

@MainActor
public final class USBIPStatusViewModel: BaseViewModel {
    @Published public var servers: [USBIPServerData] = []
    @Published public var isSubscribed = false

    private static let minAPIVersionUSBIP: Int32 = 2

    private var statusSubscription: LibboxUSBIPServerStatusSubscription?

    public func subscribe() {
        guard !isSubscribed else { return }
        isSubscribed = true

        let handler = StatusHandler(self)
        Task { [weak self] in
            do {
                let subscription = try await Task.detached { () -> LibboxUSBIPServerStatusSubscription? in
                    let client = try CommandTarget.standaloneClient()
                    var apiVersion: Int32 = 0
                    try client.getAPIVersion(&apiVersion)
                    guard apiVersion >= Self.minAPIVersionUSBIP else { return nil }
                    return try client.subscribeUSBIPServerStatus(handler)
                }.value
                guard let self else { return }
                guard let subscription else {
                    self.isSubscribed = false
                    self.servers = []
                    return
                }
                self.statusSubscription = subscription
            } catch {
                guard let self else { return }
                self.isSubscribed = false
                self.servers = []
            }
        }
    }

    public func cancel() {
        try? statusSubscription?.close()
        statusSubscription = nil
        isSubscribed = false
        servers = []
    }

    public func server(tag: String) -> USBIPServerData? {
        servers.first { $0.serverTag == tag }
    }

    private final class StatusHandler: NSObject, LibboxUSBIPServerStatusHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: USBIPStatusViewModel?

        init(_ viewModel: USBIPStatusViewModel?) {
            self.viewModel = viewModel
        }

        func onStatusUpdate(_ status: LibboxUSBIPServerStatusUpdate?) {
            guard let status else { return }
            let servers = Self.convertUpdate(status)
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isSubscribed else { return }
                viewModel.servers = servers
            }
        }

        /// A remote server without a usbip-server (or an older server) ends the stream silently,
        /// matching the daemon's NotFound/Unavailable handling. Clear state without an alert so the
        /// Services section just stays hidden instead of nagging the user.
        func onError(_: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isSubscribed else { return }
                viewModel.isSubscribed = false
                viewModel.statusSubscription = nil
                viewModel.servers = []
            }
        }

        private static func convertUpdate(_ status: LibboxUSBIPServerStatusUpdate) -> [USBIPServerData] {
            var servers: [USBIPServerData] = []
            if let iterator = status.servers() {
                while iterator.hasNext() {
                    if let server = iterator.next() {
                        servers.append(convertServer(server))
                    }
                }
            }
            return servers
        }

        private static func convertServer(_ server: LibboxUSBIPServerStatus) -> USBIPServerData {
            var devices: [USBSharedDeviceData] = []
            if let iterator = server.devices() {
                while iterator.hasNext() {
                    if let device = iterator.next() {
                        devices.append(convertDevice(device))
                    }
                }
            }
            return USBIPServerData(id: server.serverTag, serverTag: server.serverTag, devices: devices)
        }

        private static func convertDevice(_ device: LibboxUSBSharedDevice) -> USBSharedDeviceData {
            let interfaces = device.interfaces()?.toInterfaceDataArray() ?? []
            return USBSharedDeviceData(
                id: device.stableID.isEmpty ? device.busID : device.stableID,
                busID: device.busID,
                stableID: device.stableID,
                backend: device.backend,
                state: device.state,
                deviceID: device.deviceID,
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
    }
}
