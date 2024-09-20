import Foundation
import Libbox
import SwiftUI
import UniformTypeIdentifiers

public extension Profile {
    func toContent() throws -> LibboxProfileContent {
        let content = LibboxProfileContent()
        content.name = name
        content.type = Int32(type.rawValue)
        content.config = try read()
        if type != .local {
            content.remotePath = remoteURL!
        }
        if type == .remote {
            content.autoUpdate = autoUpdate
            content.autoUpdateInterval = autoUpdateInterval
            if let lastUpdated {
                content.lastUpdated = Int64(lastUpdated.timeIntervalSince1970)
            }
        }
        return content
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

    func importProfile() async throws {
        let nextProfileID = try await ProfileManager.nextID()
        let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
        try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
        let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
        try config.write(to: profileConfig, atomically: true, encoding: .utf8)
        var lastUpdatedAt: Date?
        if lastUpdated > 0 {
            lastUpdatedAt = Date(timeIntervalSince1970: Double(lastUpdated))
        }
        try await ProfileManager.create(Profile(name: name, type: ProfileType(rawValue: Int(type))!, path: profileConfig.relativePath, remoteURL: remotePath, autoUpdate: autoUpdate, autoUpdateInterval: autoUpdateInterval, lastUpdated: lastUpdatedAt))
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
    static var profile: UTType { .init(exportedAs: "io.nekohasekai.sfavt.profile") }
}
