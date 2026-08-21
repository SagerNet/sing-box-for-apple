import BinaryCodable
import Foundation
import LegacyBinaryCodable

/// BinaryCodable 3 replaced the binary format of version 2 without any in-band version
/// marker, and the two are not cross-compatible. Top-level primitives happen to encode
/// identically, but keyed and unkeyed containers do not, so data written by an older
/// release of the app can only be read by the stripped-down version 2 decoder shipped as
/// LegacyBinaryCodable.
public func decodeBinary<T: Decodable>(_ type: T.Type = T.self, from data: Data) throws -> T {
    do {
        return try BinaryDecoder().decode(type, from: data)
    } catch {
        return try LegacyBinaryDecoder().decode(type, from: data)
    }
}
