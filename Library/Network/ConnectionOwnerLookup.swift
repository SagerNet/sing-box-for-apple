#if os(macOS) || JAILBREAK
    import Foundation
    import Libbox

    public enum ConnectionOwnerLookup {
        public struct Result {
            public let userId: Int32
            public let userName: String
            public let processPath: String
        }

        public static func find(
            ipProtocol: Int32,
            sourceAddress: String,
            sourcePort: Int32,
            destinationAddress: String,
            destinationPort: Int32
        ) -> Result? {
            var error: NSError?
            guard let result = LibboxFindConnectionOwner(
                ipProtocol,
                sourceAddress,
                sourcePort,
                destinationAddress,
                destinationPort,
                &error
            ) else {
                return nil
            }
            return Result(
                userId: result.userId,
                userName: result.userName,
                processPath: result.processPath
            )
        }
    }
#endif
