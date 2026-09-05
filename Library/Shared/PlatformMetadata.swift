import Foundation
#if os(iOS) || os(tvOS)
    import DeviceKit
#endif

public enum PlatformMetadata {
    public static func json(_ additional: [String: Any] = [:]) -> String {
        var metadata: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        #if os(macOS)
            if let model = sysctlString("hw.model") {
                metadata["model"] = model
            }
            metadata["systemExtension"] = Variant.useSystemExtension
        #else
            if let model = sysctlString("hw.machine") {
                metadata["model"] = model
            }
        #endif
        #if os(iOS) || os(tvOS)
            metadata["device"] = Device.current.safeDescription
        #endif
        metadata.merge(additional) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
