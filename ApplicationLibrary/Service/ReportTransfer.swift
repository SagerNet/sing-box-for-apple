import BinaryCodable
import Foundation
import Library

public enum ReportType: String, Codable {
    case crash
    case oom

    public var directoryName: String {
        switch self {
        case .crash: return "crash_reports"
        case .oom: return "oom_reports"
        }
    }
}

public enum ReportTransferMessageType: UInt8 {
    case error = 0
    case report = 1
    case complete = 2
    case ack = 3
}

public struct ReportTransferManifest: Codable {
    public var reportType: ReportType
    public var timestamp: TimeInterval
    public var totalBytes: UInt64
    public var files: [ReportTransferManifestFile]

    public init(reportType: ReportType, timestamp: TimeInterval, totalBytes: UInt64, files: [ReportTransferManifestFile]) {
        self.reportType = reportType
        self.timestamp = timestamp
        self.totalBytes = totalBytes
        self.files = files
    }
}

public struct ReportTransferManifestFile: Codable {
    public var name: String
    public var size: UInt64

    public init(name: String, size: UInt64) {
        self.name = name
        self.size = size
    }
}

public struct ReportTransferError: LocalizedError {
    public let errorDescription: String?

    public init(_ message: String) {
        errorDescription = message
    }
}

public enum ReportTransferService {
    public static let applicationServiceName = "sing-box:report-transfer"
    public static let fileChunkSize = 64 * 1024
}

public enum ReportTransferMessage {
    public static func encodeReport(_ manifest: ReportTransferManifest) throws -> Data {
        var data = Data([ReportTransferMessageType.report.rawValue])
        try data.append(BinaryEncoder().encode(manifest))
        return data
    }

    public static func encodeComplete() -> Data {
        Data([ReportTransferMessageType.complete.rawValue])
    }

    public static func encodeAck() -> Data {
        Data([ReportTransferMessageType.ack.rawValue])
    }

    public static func encodeError(_ message: String) -> Data {
        var data = Data([ReportTransferMessageType.error.rawValue])
        data.append(Data(message.utf8))
        return data
    }

    public static func decodeType(_ data: Data) -> ReportTransferMessageType? {
        guard !data.isEmpty else { return nil }
        return ReportTransferMessageType(rawValue: data[0])
    }

    public static func decodeReport(_ data: Data) throws -> ReportTransferManifest {
        try BinaryDecoder().decode(ReportTransferManifest.self, from: data.dropFirst())
    }

    public static func decodeError(_ data: Data) -> String {
        String(data: data.dropFirst(), encoding: .utf8) ?? "Unknown error"
    }
}
