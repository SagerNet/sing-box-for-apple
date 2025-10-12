import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class NewProfileViewModel: ObservableObject {
    @Published public var isSaving = false
    @Published public var profileName = ""
    #if !os(tvOS)
        @Published public var profileType = ProfileType.local
    #else
        @Published public var profileType = ProfileType.remote
    #endif
    @Published public var fileImport = false
    @Published public var fileURL: URL?
    @Published public var remotePath = ""
    @Published public var autoUpdate = true
    @Published public var autoUpdateInterval: Int32 = 60
    @Published public var pickerPresented = false
    @Published public var alert: Alert?

    public init(importRequest: NewProfileView.ImportRequest? = nil) {
        if let importRequest {
            profileName = importRequest.name
            profileType = .remote
            remotePath = importRequest.url
        }
    }

    public func resetFields() {
        profileName = ""
        profileType = .local
        fileImport = false
        fileURL = nil
        remotePath = ""
    }

    public func createProfile(environments: ExtensionEnvironments, dismiss: DismissAction) async {
        defer {
            isSaving = false
        }
        if profileName.isEmpty {
            alert = Alert(errorMessage: String(localized: "Missing profile name"))
            return
        }
        if remotePath.isEmpty {
            if profileType == .icloud {
                alert = Alert(errorMessage: String(localized: "Missing path"))
                return
            } else if profileType == .remote {
                alert = Alert(errorMessage: String(localized: "Missing URL"))
                return
            }
        }
        do {
            try await createProfileBackground()
        } catch {
            alert = Alert(error)
            return
        }
        environments.profileUpdate.send()
        dismiss()
        #if os(macOS)
            resetFields()
        #endif
    }

    private nonisolated func createProfileBackground() async throws {
        let nextProfileID = try await ProfileManager.nextID()

        var savePath = ""
        var remoteURL: String?
        var lastUpdated: Date?

        let profileName = await profileName
        let profileType = await profileType
        let fileImport = await fileImport
        let fileURL = await fileURL
        let remotePath = await remotePath
        let autoUpdate = await autoUpdate
        let autoUpdateInterval = await autoUpdateInterval

        if profileType == .local {
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            if fileImport {
                guard let fileURL else {
                    throw NSError(domain: "Missing file", code: 0)
                }
                if !fileURL.startAccessingSecurityScopedResource() {
                    throw NSError(domain: "Missing access to selected file", code: 0)
                }
                defer {
                    fileURL.stopAccessingSecurityScopedResource()
                }
                try String(contentsOf: fileURL).write(to: profileConfig, atomically: true, encoding: .utf8)
            } else {
                try "{}".write(to: profileConfig, atomically: true, encoding: .utf8)
            }
            savePath = profileConfig.relativePath
        } else if profileType == .icloud {
            if !FileManager.default.fileExists(atPath: FilePath.iCloudDirectory.path) {
                try FileManager.default.createDirectory(at: FilePath.iCloudDirectory, withIntermediateDirectories: true)
            }
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(remotePath, isDirectory: false)
            _ = saveURL.startAccessingSecurityScopedResource()
            defer {
                saveURL.stopAccessingSecurityScopedResource()
            }
            do {
                _ = try String(contentsOf: saveURL)
            } catch {
                try "{}".write(to: saveURL, atomically: true, encoding: .utf8)
            }
            savePath = remotePath
        } else if profileType == .remote {
            let remoteContent = try HTTPClient().getString(remotePath)
            var error: NSError?
            LibboxCheckConfig(remoteContent, &error)
            if let error {
                throw error
            }
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try remoteContent.write(to: profileConfig, atomically: true, encoding: .utf8)
            savePath = profileConfig.relativePath
            remoteURL = remotePath
            lastUpdated = .now
        }
        try await ProfileManager.create(Profile(
            name: profileName,
            type: profileType,
            path: savePath,
            remoteURL: remoteURL,
            autoUpdate: autoUpdate,
            autoUpdateInterval: autoUpdateInterval,
            lastUpdated: lastUpdated
        ))
        if profileType == .remote {
            #if os(iOS) || os(tvOS)
                try UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
        }
    }
}
