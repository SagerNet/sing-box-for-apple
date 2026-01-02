import Foundation

struct EncodedBlock {
    static let qrsURLPrefix = "https://qrss.netlify.app/#"
    var indices: [Int]
    var data: Data
    let k: Int
    let bytes: Int
    let checksum: UInt32

    // Binary format: degree(4) + indices(4*n) + k(4) + bytes(4) + checksum(4) + data
    func toBinary() -> Data {
        var result = Data()

        // Write degree (number of indices)
        var degree = UInt32(indices.count).littleEndian
        result.append(Data(bytes: &degree, count: 4))

        // Write indices
        for index in indices {
            var idx = UInt32(index).littleEndian
            result.append(Data(bytes: &idx, count: 4))
        }

        // Write k, bytes, checksum
        var kVal = UInt32(k).littleEndian
        var bytesVal = UInt32(bytes).littleEndian
        var checksumVal = checksum.littleEndian
        result.append(Data(bytes: &kVal, count: 4))
        result.append(Data(bytes: &bytesVal, count: 4))
        result.append(Data(bytes: &checksumVal, count: 4))

        // Write data
        result.append(data)

        return result
    }

    static func fromBinary(_ binary: Data) -> EncodedBlock? {
        guard binary.count >= 16 else { return nil }

        var offset = 0

        let degree = binary.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
        offset += 4

        guard binary.count >= 4 + Int(degree) * 4 + 12 else { return nil }

        var indices: [Int] = []
        for _ in 0 ..< degree {
            let idx = binary.withUnsafeBytes {
                $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            indices.append(Int(idx))
            offset += 4
        }

        let k = Int(binary.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        })
        offset += 4

        let bytes = Int(binary.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        })
        offset += 4

        let checksum = binary.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
        offset += 4

        let data = binary.subdata(in: offset ..< binary.count)

        return EncodedBlock(indices: indices, data: data, k: k, bytes: bytes, checksum: checksum)
    }

    func toBase64() -> String {
        toBinary().base64EncodedString()
    }

    func toQRSString() -> String {
        Self.qrsURLPrefix + toBase64()
    }

    static func fromQRSString(_ string: String) -> EncodedBlock? {
        var content = string
        if content.hasPrefix("http"), let hashIndex = content.firstIndex(of: "#") {
            content = String(content[content.index(after: hashIndex)...])
        }
        return fromBase64(content)
    }

    static func fromBase64(_ string: String) -> EncodedBlock? {
        guard let data = Data(base64Encoded: string, options: .ignoreUnknownCharacters) else {
            #if DEBUG
                print("[EncodedBlock] Base64 decode failed for string of length \(string.count)")
            #endif
            return nil
        }
        #if DEBUG
            print("[EncodedBlock] Base64 decoded: \(data.count) bytes")
        #endif
        guard let block = fromBinary(data) else {
            #if DEBUG
                print("[EncodedBlock] fromBinary failed")
                if data.count >= 4 {
                    let degree = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
                    print("[EncodedBlock] degree=\(degree), expected size=\(4 + Int(degree) * 4 + 12), actual=\(data.count)")
                }
            #endif
            return nil
        }
        return block
    }
}
