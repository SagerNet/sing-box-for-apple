#if os(macOS)
    import Foundation
    import SystemExtensions

    public class SystemExtension: NSObject, OSSystemExtensionRequestDelegate {
        private let forceUpdate: Bool
        private let semaphore = DispatchSemaphore(value: 0)
        private var result: OSSystemExtensionRequest.Result?
        private var properties: [OSSystemExtensionProperties]?
        private var error: Error?

        private init(forceUpdate: Bool = false) {
            self.forceUpdate = forceUpdate
        }

        public func request(_: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
            if forceUpdate {
                return .replace
            }
            if existing.bundleIdentifier == ext.bundleIdentifier,
               existing.bundleVersion == ext.bundleVersion
            {
                return .cancel
            } else {
                return .replace
            }
        }

        public func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
            semaphore.signal()
        }

        public func request(_: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
            self.result = result
            semaphore.signal()
        }

        public func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
            self.error = error
            semaphore.signal()
        }

        public func request(_: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
            self.properties = properties
            semaphore.signal()
        }

        public func submitAndWait() throws -> OSSystemExtensionRequest.Result? {
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: FilePath.packageName + ".system", queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
            semaphore.wait()
            if let error {
                throw error
            }
            return result
        }

        public func getProperties() throws -> [OSSystemExtensionProperties] {
            let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: FilePath.packageName + ".system", queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
            semaphore.wait()
            if let error {
                throw error
            }
            return properties!
        }

        public static func isInstalled() async -> Bool {
            await (try? Task.detached {
                do {
                    let propList = try SystemExtension().getProperties()
                    if propList.isEmpty {
                        return false
                    }
                    for extensionProp in propList {
                        if !extensionProp.isAwaitingUserApproval, !extensionProp.isUninstalling {
                            return true
                        }
                    }
                } catch {
                    NSLog(error.localizedDescription)
                }
                return false
            }.result.get()) == true
        }

        public static func install(forceUpdate: Bool = false) async throws -> OSSystemExtensionRequest.Result? {
            try await Task.detached {
                try SystemExtension(forceUpdate: forceUpdate).submitAndWait()
            }.result.get()
        }
    }
#endif
