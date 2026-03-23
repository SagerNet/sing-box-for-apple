import Foundation
import Libbox

enum ConnectionOwnerLookup {
    struct Result {
        let userId: Int32
        let userName: String
        let processPath: String
    }

    static func find(
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
