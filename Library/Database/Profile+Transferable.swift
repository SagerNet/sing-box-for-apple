import Foundation
import Libbox
import SwiftUI
import UniformTypeIdentifiers

public extension Profile {
    func toContent() throws -> LibboxProfileContent {
        let content = LibboxProfileContent()
        content.name = name
        switch type {
        case .local, .icloud:
            content.type = LibboxProfileTypeLocal
        case .remote:
            content.type = LibboxProfileTypeRemote
        }
        content.config = try read()
        if type == .remote {
            content.remotePath = remoteURL!
        }
        if type == .remote {
            content.autoUpdate = autoUpdate
            content.autoUpdateInterval = autoUpdateInterval
            if let lastUpdated {
                content.lastUpdated = Int64(lastUpdated.timeIntervalSince1970 * 1000)
            }
        }
        return content
    }
}

public func dateFromTimestamp(_ timestamp: Int64) -> Date {
    if timestamp > 100_000_000_000 {
        return Date(timeIntervalSince1970: Double(timestamp) / 1000)
    } else {
        return Date(timeIntervalSince1970: Double(timestamp))
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension Profile: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { profile in
            try TypedProfile(profile.toContent())
        }
    }
}

public extension LibboxProfileContent {
    static func from(_ data: Data) throws -> LibboxProfileContent {
        var error: NSError?
        let content = LibboxDecodeProfileContent(data, &error)
        if let error {
            throw error
        }
        return content!
    }

    @discardableResult
    func importProfile() async throws -> Profile {
        let nextProfileID = try await ProfileManager.nextID()
        let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
        try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
        let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
        try config.write(to: profileConfig, atomically: true, encoding: .utf8)
        var lastUpdatedAt: Date?
        if lastUpdated > 0 {
            lastUpdatedAt = dateFromTimestamp(lastUpdated)
        }
        let uniqueProfileName = try await ProfileManager.uniqueName(name)
        let profile = Profile(name: uniqueProfileName, type: ProfileType(rawValue: Int(type))!, path: profileConfig.relativePath, remoteURL: remotePath, autoUpdate: autoUpdate, autoUpdateInterval: autoUpdateInterval, lastUpdated: lastUpdatedAt)
        try await ProfileManager.create(profile)
        await SharedPreferences.selectedProfileID.set(profile.mustID)
        return profile
    }

    func generateShareFile() throws -> URL {
        let shareDirectory = FilePath.cacheDirectory.appendingPathComponent("share", isDirectory: true)
        try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        let shareFile = shareDirectory.appendingPathComponent("\(name).bpf")
        try encode()!.write(to: shareFile)
        return shareFile
    }
}

public extension String {
    func generateShareFile(name: String) throws -> URL {
        let shareDirectory = FilePath.cacheDirectory.appendingPathComponent("share", isDirectory: true)
        try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        let shareFile = shareDirectory.appendingPathComponent(name)
        try write(to: shareFile, atomically: true, encoding: .utf8)
        return shareFile
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct TypedProfile: Transferable, Codable {
    public let content: LibboxProfileContent
    public init(_ content: LibboxProfileContent) {
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        try self.init(.from(data))
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .profile) { typed in
            try SentTransferredFile(typed.content.generateShareFile(), allowAccessingOriginalFile: true)
        } importing: { received in
            try TypedProfile(.from(Data(contentsOf: received.file)))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(content.encode()!)
    }
}

public extension UTType {
    static let profile = UTType(exportedAs: AppConfiguration.profileUTType)
}

#if !os(tvOS)

    // MARK: - FileDocument for Export

    public struct ProfileExportDocument: FileDocument {
        public static var readableContentTypes: [UTType] { [.profile] }

        public let data: Data
        public let filename: String

        public init(content: LibboxProfileContent) throws {
            guard let encoded = content.encode() else {
                throw NSError(domain: "ProfileExportDocument", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode profile"])
            }
            data = encoded
            filename = "\(content.name).bpf"
        }

        public init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.data = data
            filename = "profile.bpf"
        }

        public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }

    public struct ProfileJSONExportDocument: FileDocument {
        public static var readableContentTypes: [UTType] { [.json] }

        public let content: String
        public let filename: String

        public init(jsonContent: String, name: String) {
            content = jsonContent
            filename = "\(name).json"
        }

        public init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents,
                  let content = String(data: data, encoding: .utf8)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.content = content
            filename = "profile.json"
        }

        public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            guard let data = content.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            return FileWrapper(regularFileWithContents: data)
        }
    }

    public struct ProfileAnyExportDocument: FileDocument {
        public static var readableContentTypes: [UTType] { [.data, .json] }

        public let data: Data
        public let filename: String
        public let contentType: UTType

        public init(profile: ProfileExportDocument) {
            data = profile.data
            filename = profile.filename
            contentType = .data
        }

        public init(json: ProfileJSONExportDocument) {
            data = json.content.data(using: .utf8) ?? Data()
            filename = json.filename
            contentType = .json
        }

        public init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.data = data
            filename = "profile"
            contentType = .data
        }

        public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
#endif
