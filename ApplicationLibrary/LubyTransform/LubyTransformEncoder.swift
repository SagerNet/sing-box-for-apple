import Foundation
import zlib

final class LubyTransformEncoder {
    let k: Int
    let sliceSize: Int
    let checksum: UInt32
    let bytes: Int
    private let sourceBlocks: [Data]

    init(data: Data, sliceSize: Int = 512, compress: Bool = true) {
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
        var stream = z_stream()

        // Use 15 for zlib format (with header/trailer) to match pako's default
        guard deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        let destSize = Int(deflateBound(&stream, UInt(data.count)))
        var dest = Data(count: destSize)

        let result = data.withUnsafeBytes { srcPtr -> Int32 in
            dest.withUnsafeMutableBytes { destPtr -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: srcPtr.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destPtr.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destSize)
                return deflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else { return nil }
        dest.count = Int(stream.total_out)
        return dest
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
        guard k > 1 else { return k }
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
        if let i = cumulative.firstIndex(where: { random < $0 }) {
            return i + 1
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

    #if DEBUG
        static func runSelfTest() -> Bool {
            // Test 1: Round-trip tests with various sizes
            let testCases: [(size: Int, sliceSize: Int)] = [
                (1, 100),
                (100, 100),
                (1000, 100),
                (1031, 100),
            ]

            for (size, sliceSize) in testCases {
                let data = Data((0 ..< size).map { UInt8($0 % 256) })
                let encoder = LubyTransformEncoder(data: data, sliceSize: sliceSize, compress: true)
                let decoder = LubyTransformDecoder()

                var blockCount = 0
                for block in encoder.fountain() {
                    blockCount += 1
                    if blockCount > encoder.k * 3 {
                        print("LubyTransform self-test FAILED: too many blocks for size=\(size)")
                        return false
                    }
                    do {
                        if try decoder.addBlock(block) { break }
                    } catch {
                        print("LubyTransform self-test FAILED: \(error)")
                        return false
                    }
                }

                do {
                    let decoded = try decoder.getDecoded()
                    if decoded != data {
                        print("LubyTransform self-test FAILED: data mismatch for size=\(size)")
                        return false
                    }
                } catch {
                    print("LubyTransform self-test FAILED: \(error)")
                    return false
                }
            }

            // Test 2: TypeScript compatibility (decode blocks generated by TypeScript)
            // Test vector: 5 bytes [0xAB, 0xCD, 0xEF, 0x12, 0x34], uncompressed, sliceSize=10
            let tsBlockBase64 = "AQAAAAAAAAABAAAABQAAALt8DL6rze8SNAAAAAAA"
            let expectedData = Data([0xAB, 0xCD, 0xEF, 0x12, 0x34])

            guard let blockData = Data(base64Encoded: tsBlockBase64),
                  let block = EncodedBlock.fromBinary(blockData)
            else {
                print("LubyTransform self-test FAILED: cannot parse TypeScript block")
                return false
            }

            let tsDecoder = LubyTransformDecoder()
            do {
                _ = try tsDecoder.addBlock(block)
                let decoded = try tsDecoder.getDecoded()
                if decoded != expectedData {
                    print("LubyTransform self-test FAILED: TypeScript compatibility mismatch")
                    print("Expected: \(expectedData.map { String(format: "%02X", $0) }.joined())")
                    print("Got: \(decoded.map { String(format: "%02X", $0) }.joined())")
                    return false
                }
            } catch {
                print("LubyTransform self-test FAILED: TypeScript decode error: \(error)")
                return false
            }

            print("LubyTransform self-test PASSED (including TypeScript compatibility)")
            return true
        }
    #endif
}
