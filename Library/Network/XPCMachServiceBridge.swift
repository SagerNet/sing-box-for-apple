#if os(macOS) || JAILBREAK
    import Foundation

    // NSXPCConnection(machServiceName:options:) and NSXPCListener(machServiceName:)
    // are API_UNAVAILABLE(iOS) in the SDK, but the implementations exist in the
    // runtime and work for a launchd-registered mach service on a jailbroken device.
    public enum XPCMachServiceBridge {
        static func makeConnection(machServiceName name: String, privileged: Bool = false) -> NSXPCConnection {
            #if os(macOS)
                var options: NSXPCConnection.Options = []
                if privileged {
                    options.insert(.privileged)
                }
                return NSXPCConnection(machServiceName: name, options: options)
            #else
                // NSXPCConnectionPrivileged == 1 << 12
                let options: UInt = privileged ? (1 << 12) : 0
                let selector = NSSelectorFromString("initWithMachServiceName:options:")
                let allocated = (NSXPCConnection.self as AnyObject).perform(NSSelectorFromString("alloc"))!
                let method = class_getInstanceMethod(NSXPCConnection.self, selector)!
                typealias InitFunction = @convention(c) (UnsafeMutableRawPointer, Selector, NSString, UInt) -> Unmanaged<NSXPCConnection>
                let initCall = unsafeBitCast(method_getImplementation(method), to: InitFunction.self)
                return initCall(allocated.toOpaque(), selector, name as NSString, options).takeRetainedValue()
            #endif
        }

        public static func makeListener(machServiceName name: String) -> NSXPCListener {
            #if os(macOS)
                return NSXPCListener(machServiceName: name)
            #else
                let selector = NSSelectorFromString("initWithMachServiceName:")
                let allocated = (NSXPCListener.self as AnyObject).perform(NSSelectorFromString("alloc"))!
                let method = class_getInstanceMethod(NSXPCListener.self, selector)!
                typealias InitFunction = @convention(c) (UnsafeMutableRawPointer, Selector, NSString) -> Unmanaged<NSXPCListener>
                let initCall = unsafeBitCast(method_getImplementation(method), to: InitFunction.self)
                return initCall(allocated.toOpaque(), selector, name as NSString).takeRetainedValue()
            #endif
        }
    }
#endif
