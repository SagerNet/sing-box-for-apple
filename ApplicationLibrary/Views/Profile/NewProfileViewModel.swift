import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class NewProfileViewModel: BaseViewModel {
    @Published public var isSaving = false
    @Published public var createSucceeded = false
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

    public let isImport: Bool

    public init(importRequest: NewProfileView.ImportRequest? = nil, localImportRequest: NewProfileView.LocalImportRequest? = nil) {
        isImport = importRequest != nil
        super.init()
        if let importRequest {
            profileName = importRequest.name
            profileType = .remote
            remotePath = importRequest.url
        } else if let localImportRequest {
            profileName = localImportRequest.name
            profileType = .local
            fileImport = true
            fileURL = localImportRequest.fileURL
        }
    }

    public func resetFields() {
        profileName = ""
        profileType = .local
        fileImport = false
        fileURL = nil
        remotePath = ""
    }

    public func createProfile(
        environments: ExtensionEnvironments,
        dismiss: DismissAction? = nil,
        onSuccess: ((Profile) async -> Void)? = nil,
        sendUpdateNotification: Bool = true
    ) async {
        defer { isSaving = false }

        guard !profileName.isEmpty else {
            alert = AlertState(errorMessage: String(localized: "Missing profile name"))
            return
        }

        if profileType == .icloud, remotePath.isEmpty {
            alert = AlertState(errorMessage: String(localized: "Missing path"))
            return
        }

        if profileType == .remote, remotePath.isEmpty {
            alert = AlertState(errorMessage: String(localized: "Missing URL"))
            return
        }

        let createdProfile: Profile
        do {
            createdProfile = try await createProfileBackground()
        } catch {
            alert = AlertState(action: "create profile", error: error)
            return
        }

        if let onSuccess {
            await onSuccess(createdProfile)
        }
        if sendUpdateNotification {
            environments.profileUpdate.send()
        }
        createSucceeded = true
        dismiss?()

        #if os(macOS)
            resetFields()
        #endif
    }

    private nonisolated func createProfileBackground() async throws -> Profile {
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
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try await BlockingIO.run {
                try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
                if fileImport {
                    guard let fileURL else {
                        throw NSError(domain: "NewProfileViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing file")])
                    }
                    try fileURL.withRequiredSecurityScopedAccess(
                        or: NSError(domain: "NewProfileViewModel", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing access to selected file")])
                    ) {
                        try String(contentsOf: fileURL).write(to: profileConfig, atomically: true, encoding: .utf8)
                    }
                } else {
                    try "{}".write(to: profileConfig, atomically: true, encoding: .utf8)
                }
            }
            savePath = profileConfig.relativePath
        } else if profileType == .icloud {
            let iCloudDirectory = FilePath.iCloudDirectory
            try await BlockingIO.run {
                if !FileManager.default.fileExists(atPath: iCloudDirectory.path) {
                    try FileManager.default.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
                }
                let saveURL = iCloudDirectory.appendingPathComponent(remotePath, isDirectory: false)
                do {
                    _ = try String(contentsOf: saveURL)
                } catch {
                    try "{}".write(to: saveURL, atomically: true, encoding: .utf8)
                }
            }
            savePath = remotePath
        } else if profileType == .remote {
            let remoteContent = try await HTTPClient.getStringAsync(remotePath)
            try await BlockingIO.run {
                var error: NSError?
                LibboxCheckConfig(remoteContent, &error)
                if let error {
                    throw error
                }
            }
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try await BlockingIO.run {
                try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
                try remoteContent.write(to: profileConfig, atomically: true, encoding: .utf8)
            }
            savePath = profileConfig.relativePath
            remoteURL = remotePath
            lastUpdated = .now
        }

        let uniqueProfileName = try await ProfileManager.uniqueName(profileName)

        // Create Profile object - GRDB will set its ID after insertion
        let profile = Profile(
            name: uniqueProfileName,
            type: profileType,
            path: savePath,
            remoteURL: remoteURL,
            autoUpdate: autoUpdate,
            autoUpdateInterval: autoUpdateInterval,
            lastUpdated: lastUpdated
        )
        try await ProfileManager.create(profile)

        if profileType == .remote {
            #if os(iOS) || os(tvOS)
                try UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
        }

        // Return the profile object which now has its ID set by GRDB
        return profile
    }
}
