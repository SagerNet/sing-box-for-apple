import Library
import SwiftUI

@MainActor
public struct USBIPDeviceView: View {
    let device: USBSharedDeviceData

    public init(device: USBSharedDeviceData) {
        self.device = device
    }

    public var body: some View {
        FormView {
            Section("Identity") {
                if !device.product.isEmpty {
                    FormTextItem("Product", device.product)
                }
                FormTextItem("VID:PID", usbFormatVidPid(device.vendorID, device.productID))
                if !device.serial.isEmpty {
                    FormTextItem("Serial number", device.serial)
                }
                if device.bcdDevice > 0 {
                    FormTextItem("Version", bcdToVersion(device.bcdDevice))
                }
            }
            Section("Connection") {
                if !device.busID.isEmpty {
                    FormTextItem("Bus ID", device.busID)
                }
                if let backend = usbBackendLabel(device.backend) {
                    FormTextItem("Backend", backend)
                }
                if let speed = usbSpeedLabel(device.speed) {
                    FormTextItem("Speed", speed)
                }
                if device.busNum > 0 || device.devNum > 0 {
                    FormTextItem("Bus / Device", "\(device.busNum) · \(device.devNum)")
                }
            }
            Section("Class & Interfaces") {
                FormTextItem("Device class", deviceClassText)
                if device.numConfigurations > 0 {
                    FormTextItem("Configurations", configurationsText)
                }
                ForEach(device.interfaces) { iface in
                    FormTextItem("Interface \(iface.id + 1)", usbClassTriplet(iface.interfaceClass, iface.interfaceSubClass, iface.interfaceProtocol))
                }
            }
        }
        .navigationTitle(device.displayName)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var deviceClassText: String {
        device.deviceClass == 0
            ? String(localized: "Defined at interface level")
            : usbClassTriplet(device.deviceClass, device.deviceSubClass, device.deviceProtocol)
    }

    private var configurationsText: String {
        device.configurationValue > 0
            ? "\(device.numConfigurations) (active #\(device.configurationValue))"
            : "\(device.numConfigurations)"
    }
}
