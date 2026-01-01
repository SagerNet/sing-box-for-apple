import Compression
import Foundation

final class LubyTransformDecoder {
    private(set) var decodedData: [Data?] = []
    private(set) var decodedCount = 0
    private(set) var encodedCount = 0
    private var encodedBlocks: Set<BlockWrapper> = []
    private var encodedBlockKeyMap: [String: BlockWrapper] = [:]
    private var encodedBlockSubkeyMap: [String: Set<BlockWrapper>] = [:]
    private var encodedBlockIndexMap: [Int: Set<BlockWrapper>] = [:]
    private var disposedEncodedBlocks: [Int: [() -> Void]] = [:]
    private(set) var meta: EncodedBlock?

    var k: Int { meta?.k ?? 0 }
    var progress: Double {
        guard k > 0 else { return 0 }
        return Double(decodedCount) / Double(k)
    }

    var isComplete: Bool { meta != nil && decodedCount == k }

    private class BlockWrapper: Hashable {
        var block: EncodedBlock
        let id = UUID()

        init(_ block: EncodedBlock) { self.block = block }

        static func == (lhs: BlockWrapper, rhs: BlockWrapper) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum DecoderError: Error {
        case checksumMismatch
        case incomplete
        case noMeta
    }

    @discardableResult
    func addBlock(_ block: EncodedBlock) throws -> Bool {
        if meta == nil {
            meta = block
            decodedData = Array(repeating: nil, count: block.k)
        }

        guard block.checksum == meta?.checksum else {
            throw DecoderError.checksumMismatch
        }

        encodedCount += 1

        var mutableBlock = block
        mutableBlock.indices.sort()
        let wrapper = BlockWrapper(mutableBlock)
        propagateDecoded(key: indicesToKey(mutableBlock.indices), wrapper: wrapper)

        return decodedCount == k
    }

    private func indicesToKey(_ indices: [Int]) -> String {
        indices.map(String.init).joined(separator: ",")
    }

    private func xorData(_ a: Data, _ b: Data) -> Data {
        var result = a
        let count = min(a.count, b.count)
        for i in 0 ..< count {
            result[i] ^= b[i]
        }
        return result
    }

    private func propagateDecoded(key: String, wrapper: BlockWrapper) {
        var block = wrapper.block
        var indices = block.indices
        var indicesSet = Set(indices)

        if encodedBlockKeyMap[key] != nil || indices.allSatisfy({ decodedData[$0] != nil }) {
            return
        }

        // XOR with already decoded blocks to reduce degree
        if indices.count > 1 {
            for index in indices {
                if let decoded = decodedData[index] {
                    block.data = xorData(block.data, decoded)
                    indicesSet.remove(index)
                }
            }
            if indicesSet.count != indices.count {
                indices = Array(indicesSet).sorted()
                block.indices = indices
            }
        }

        // Try subset matching for blocks with degree > 2
        if indices.count > 2 {
            var subkeys: [(index: Int, subkey: String)] = []
            for index in indices {
                let subIndices = indices.filter { $0 != index }
                let subkey = indicesToKey(subIndices)
                if let subWrapper = encodedBlockKeyMap[subkey] {
                    block.data = xorData(block.data, subWrapper.block.data)
                    for i in subWrapper.block.indices {
                        indicesSet.remove(i)
                    }
                    indices = Array(indicesSet).sorted()
                    block.indices = indices
                    subkeys.removeAll()
                    break
                } else {
                    subkeys.append((index, subkey))
                }
            }

            // Store subkeys for future matching if still high degree
            if indicesSet.count > 1 {
                for (index, subkey) in subkeys {
                    let dispose = { [weak self] in
                        self?.encodedBlockSubkeyMap[subkey]?.remove(wrapper)
                    }
                    if encodedBlockSubkeyMap[subkey] == nil {
                        encodedBlockSubkeyMap[subkey] = []
                    }
                    encodedBlockSubkeyMap[subkey]?.insert(wrapper)
                    if disposedEncodedBlocks[index] == nil {
                        disposedEncodedBlocks[index] = []
                    }
                    disposedEncodedBlocks[index]?.append(dispose)
                }
            }
        }

        wrapper.block = block

        // If still degree > 1, store as pending
        if indices.count > 1 {
            encodedBlocks.insert(wrapper)
            for i in indices {
                if encodedBlockIndexMap[i] == nil {
                    encodedBlockIndexMap[i] = []
                }
                encodedBlockIndexMap[i]?.insert(wrapper)
            }

            let newKey = indicesToKey(indices)
            encodedBlockKeyMap[newKey] = wrapper

            // Check if this can decode pending supersets
            if let superset = encodedBlockSubkeyMap[newKey] {
                encodedBlockSubkeyMap.removeValue(forKey: newKey)
                for superWrapper in superset {
                    var superBlock = superWrapper.block
                    superBlock.data = xorData(superBlock.data, block.data)
                    var superIndicesSet = Set(superBlock.indices)
                    for i in indices {
                        superIndicesSet.remove(i)
                    }
                    superBlock.indices = Array(superIndicesSet).sorted()
                    superWrapper.block = superBlock
                    propagateDecoded(key: indicesToKey(superBlock.indices), wrapper: superWrapper)
                }
            }
        }
        // Degree 1: directly decode
        else if let index = indices.first, decodedData[index] == nil {
            encodedBlocks.remove(wrapper)
            disposedEncodedBlocks[index]?.forEach { $0() }
            decodedData[index] = block.data
            decodedCount += 1

            // Propagate to waiting blocks
            if let waitingBlocks = encodedBlockIndexMap[index] {
                encodedBlockIndexMap.removeValue(forKey: index)
                for waiting in waitingBlocks {
                    let waitingKey = indicesToKey(waiting.block.indices)
                    encodedBlockKeyMap.removeValue(forKey: waitingKey)
                    propagateDecoded(key: waitingKey, wrapper: waiting)
                }
            }
        }
    }

    func getDecoded() throws -> Data {
        guard decodedCount == k else {
            throw DecoderError.incomplete
        }
        guard decodedData.allSatisfy({ $0 != nil }) else {
            throw DecoderError.incomplete
        }
        guard let meta else {
            throw DecoderError.noMeta
        }

        let sliceSize = meta.data.count
        var result = Data(capacity: meta.bytes)

        for (i, block) in decodedData.enumerated() {
            guard let block else { continue }
            let start = i * sliceSize
            let copyLength = min(sliceSize, meta.bytes - start)
            if copyLength > 0 {
                result.append(block.prefix(copyLength))
            }
        }

        // Try decompression
        if let decompressed = Self.inflate(result) {
            let checksum = CRC32.checksum(decompressed, k: meta.k)
            if checksum == meta.checksum {
                return decompressed
            }
        }

        // Fallback to uncompressed
        let checksum = CRC32.checksum(result, k: meta.k)
        if checksum == meta.checksum {
            return result
        }

        throw DecoderError.checksumMismatch
    }

    private static func inflate(_ data: Data) -> Data? {
        let sourceSize = data.count
        let destinationSize = sourceSize * 10

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}
