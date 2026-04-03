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

public struct ReportTransferPayload: Codable {
    public var reportType: ReportType
    public var timestamp: TimeInterval
    public var files: [ReportTransferFile]

    public init(reportType: ReportType, timestamp: TimeInterval, files: [ReportTransferFile]) {
        self.reportType = reportType
        self.timestamp = timestamp
        self.files = files
    }
}

public struct ReportTransferFile: Codable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
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
}

public enum ReportTransferMessage {
    public static func encodeReport(_ payload: ReportTransferPayload) throws -> Data {
        var data = Data([ReportTransferMessageType.report.rawValue])
        try data.append(BinaryEncoder().encode(payload))
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

    public static func decodeReport(_ data: Data) throws -> ReportTransferPayload {
        try BinaryDecoder().decode(ReportTransferPayload.self, from: data.dropFirst())
    }

    public static func decodeError(_ data: Data) -> String {
        String(data: data.dropFirst(), encoding: .utf8) ?? "Unknown error"
    }
}
