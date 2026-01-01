import Foundation

enum CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0 ..< 256 {
            var crc = UInt32(i)
            for _ in 0 ..< 8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc = crc >> 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    static func checksum(_ data: Data, k: Int) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ UInt32(k) ^ 0xFFFF_FFFF
    }
}
