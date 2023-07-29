import Foundation

public enum Variant {
    #if os(macOS)
        public static var useSystemExtension = false
    #else
        public static let useSystemExtension = false
    #endif

    #if os(iOS)
        public static let applicationName = "SFI"
    #elseif os(macOS)
        public static let applicationName = "SFM"
    #elseif os(tvOS)
        public static let applicationName = "SFT"
    #endif
}
