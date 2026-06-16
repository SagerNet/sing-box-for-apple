import Libbox
import SwiftUI

// USB device presentation helpers, ported from the web dashboard's src/lib/usbInfo.ts so the
// native viewer renders identical labels for the same daemon.StartedService values.

func usbFormatVidPid(_ vendorID: Int32, _ productID: Int32) -> String {
    String(format: "%04x:%04x", UInt32(truncatingIfNeeded: vendorID), UInt32(truncatingIfNeeded: productID))
}

/// bcdDevice is BCD-encoded: 0x0210 -> "2.10".
func bcdToVersion(_ bcd: Int32) -> String {
    "\((bcd >> 8) & 0xFF).\((bcd >> 4) & 0x0F)\(bcd & 0x0F)"
}

/// Linux USB_SPEED_* constants, the same values the daemon reports.
func usbSpeedLabel(_ code: Int32) -> String? {
    switch code {
    case 1: return "Low Speed"
    case 2: return "Full Speed"
    case 3: return "High Speed"
    case 4: return "Wireless"
    case 5: return "SuperSpeed"
    case 6: return "SuperSpeed+"
    default: return nil
    }
}

private func usbHex2(_ value: Int32) -> String {
    String(format: "0x%02x", UInt32(truncatingIfNeeded: value))
}

/// USB-IF base class codes (bDeviceClass / bInterfaceClass).
private let usbClassNames: [Int32: String] = [
    0x01: "Audio",
    0x02: "CDC Control",
    0x03: "HID",
    0x05: "Physical",
    0x06: "Image",
    0x07: "Printer",
    0x08: "Mass Storage",
    0x09: "Hub",
    0x0A: "CDC Data",
    0x0B: "Smart Card",
    0x0D: "Content Security",
    0x0E: "Video",
    0x0F: "Personal Healthcare",
    0x10: "Audio/Video",
    0x11: "Billboard",
    0x12: "USB-C Bridge",
    0xDC: "Diagnostic",
    0xE0: "Wireless",
    0xEF: "Miscellaneous",
    0xFE: "Application Specific",
    0xFF: "Vendor Specific",
]

/// "Mass Storage · 0x06 · 0x50" — the class name (or hex) plus sub/protocol when either is set.
func usbClassTriplet(_ deviceClass: Int32, _ subClass: Int32, _ deviceProtocol: Int32) -> String {
    let name = usbClassNames[deviceClass] ?? usbHex2(deviceClass)
    if subClass > 0 || deviceProtocol > 0 {
        return "\(name) · \(usbHex2(subClass)) · \(usbHex2(deviceProtocol))"
    }
    return name
}

func usbBackendLabel(_ backend: Int32) -> String? {
    switch backend {
    case LibboxUSBBackendLinuxSysfs: return "linux-sysfs"
    case LibboxUSBBackendDynamic: return "dynamic"
    case LibboxUSBBackendDarwinIOKit: return "darwin-iokit"
    case LibboxUSBBackendWindowsVBoxUSB: return "windows-vboxusb"
    default: return nil
    }
}

struct USBDeviceStatePresentation {
    let label: LocalizedStringKey
    let color: Color
}

func usbDeviceState(_ state: Int32) -> USBDeviceStatePresentation {
    switch state {
    case LibboxUSBDeviceStateIdle:
        return USBDeviceStatePresentation(label: "Idle", color: .green)
    case LibboxUSBDeviceStateAttached:
        return USBDeviceStatePresentation(label: "Attached", color: .orange)
    case LibboxUSBDeviceStateUnavailable:
        return USBDeviceStatePresentation(label: "Unavailable", color: .red)
    default:
        return USBDeviceStatePresentation(label: "Unknown", color: Color(.systemGray))
    }
}

extension LibboxUSBSharedDeviceInterfaceIteratorProtocol {
    func toInterfaceDataArray() -> [USBInterfaceData] {
        var interfaces: [USBInterfaceData] = []
        var index = 0
        while hasNext() {
            if let iface = next() {
                interfaces.append(USBInterfaceData(
                    id: index,
                    interfaceClass: iface.interfaceClass,
                    interfaceSubClass: iface.interfaceSubClass,
                    interfaceProtocol: iface.interfaceProtocol
                ))
                index += 1
            }
        }
        return interfaces
    }
}
