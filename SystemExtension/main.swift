import Foundation
import Library
import NetworkExtension

Variant.useSystemExtension = true

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
