import Foundation

enum BinaryMeta {
    enum MetaError: Error {
        case invalidBuffer
        case invalidMeta
    }

    struct FileHeaderMeta: Codable {
        var filename: String?
        var contentType: String?
    }

    static func mergeDataArrays(_ arrays: [Data]) -> Data {
        var totalLength = 0
        for arr in arrays {
            totalLength += 4 + arr.count
        }

        var merged = Data(capacity: totalLength)
        for arr in arrays {
            let length = UInt32(arr.count)
            var bytes: [UInt8] = [
                UInt8((length >> 24) & 0xFF),
                UInt8((length >> 16) & 0xFF),
                UInt8((length >> 8) & 0xFF),
                UInt8(length & 0xFF),
            ]
            merged.append(contentsOf: bytes)
            merged.append(arr)
        }

        return merged
    }

    static func splitDataArrays(_ merged: Data) throws -> [Data] {
        var arrays: [Data] = []
        var offset = 0

        while offset < merged.count {
            guard offset + 4 <= merged.count else {
                throw MetaError.invalidBuffer
            }

            let length = merged.withUnsafeBytes { ptr -> Int in
                let b0 = Int(ptr[offset]) << 24
                let b1 = Int(ptr[offset + 1]) << 16
                let b2 = Int(ptr[offset + 2]) << 8
                let b3 = Int(ptr[offset + 3])
                return b0 | b1 | b2 | b3
            }
            offset += 4

            guard offset + length <= merged.count else {
                throw MetaError.invalidBuffer
            }

            let arr = merged.subdata(in: offset ..< offset + length)
            arrays.append(arr)
            offset += length
        }

        return arrays
    }

    static func appendFileHeaderMeta(data: Data, filename: String?, contentType: String) -> Data {
        let meta = FileHeaderMeta(filename: filename, contentType: contentType)
        guard let metaData = try? JSONEncoder().encode(meta) else {
            return data
        }
        return mergeDataArrays([metaData, data])
    }

    static func readFileHeaderMeta(buffer: Data) throws -> (data: Data, filename: String?, contentType: String) {
        let arrays = try splitDataArrays(buffer)
        guard arrays.count == 2 else {
            throw MetaError.invalidBuffer
        }

        let metaData = arrays[0]
        let data = arrays[1]

        guard let meta = try? JSONDecoder().decode(FileHeaderMeta.self, from: metaData) else {
            throw MetaError.invalidMeta
        }

        return (data, meta.filename, meta.contentType ?? "application/octet-stream")
    }
}
