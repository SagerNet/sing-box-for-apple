import Compression
import Foundation

final class LubyTransformEncoder {
    let k: Int
    let sliceSize: Int
    let checksum: UInt32
    let bytes: Int
    private let sourceBlocks: [Data]

    init(data: Data, sliceSize: Int = 500, compress: Bool = true) {
        self.sliceSize = sliceSize

        let compressed: Data
        if compress {
            compressed = Self.deflateCompress(data) ?? data
        } else {
            compressed = data
        }

        bytes = compressed.count
        sourceBlocks = Self.sliceData(compressed, sliceSize: sliceSize)
        k = sourceBlocks.count
        checksum = CRC32.checksum(data, k: k)
    }

    private static func deflateCompress(_ data: Data) -> Data? {
        let sourceSize = data.count
        let destinationSize = sourceSize + 1024

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    private static func sliceData(_ data: Data, sliceSize: Int) -> [Data] {
        var blocks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + sliceSize, data.count)
            var block = data.subdata(in: offset ..< end)
            if block.count < sliceSize {
                block.append(Data(count: sliceSize - block.count))
            }
            blocks.append(block)
            offset += sliceSize
        }
        return blocks
    }

    func createBlock(indices: [Int]) -> EncodedBlock {
        var result = Data(count: sliceSize)
        for index in indices {
            let source = sourceBlocks[index]
            for i in 0 ..< sliceSize {
                result[i] ^= source[i]
            }
        }
        return EncodedBlock(
            indices: indices,
            data: result,
            k: k,
            bytes: bytes,
            checksum: checksum
        )
    }

    // Ideal Soliton Distribution for degree selection
    private func getRandomDegree() -> Int {
        var probabilities = [Double](repeating: 0, count: k)
        probabilities[0] = 1.0 / Double(k)
        for d in 2 ... k {
            probabilities[d - 1] = 1.0 / Double(d * (d - 1))
        }

        var cumulative = [Double](repeating: 0, count: k)
        cumulative[0] = probabilities[0]
        for i in 1 ..< k {
            cumulative[i] = cumulative[i - 1] + probabilities[i]
        }

        let random = Double.random(in: 0 ... 1)
        for i in 0 ..< k {
            if random < cumulative[i] {
                return i + 1
            }
        }
        return k
    }

    private func getRandomIndices(degree: Int) -> [Int] {
        var indices = Set<Int>()
        while indices.count < degree {
            indices.insert(Int.random(in: 0 ..< k))
        }
        return Array(indices)
    }

    func fountain() -> AnyIterator<EncodedBlock> {
        AnyIterator {
            let degree = self.getRandomDegree()
            let indices = self.getRandomIndices(degree: degree)
            return self.createBlock(indices: indices)
        }
    }
}
