import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct NewProfileView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var profileName = ""
    @State private var profileType = ProfileType.local
    @State private var fileImport = false
    @State private var fileURL: URL!
    @State private var remotePath = ""
    @State private var autoUpdate = true
    @State private var autoUpdateInterval: Int32 = 60
    @State private var pickerPresented = false
    @State private var alert: Alert?

    public struct ImportRequest: Codable, Hashable {
        public let name: String
        public let url: String
    }

    public init(_ importRequest: ImportRequest? = nil) {
        if let importRequest {
            _profileName = .init(initialValue: importRequest.name)
            _profileType = .init(initialValue: .remote)
            _remotePath = .init(initialValue: importRequest.url)
        }
    }

    public var body: some View {
        FormView {
            FormItem(String(localized: "Name")) {
                TextField("Name", text: $profileName, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
            }
            Picker(selection: $profileType) {
                #if !os(tvOS)
                    Text("Local").tag(ProfileType.local)
                    Text("iCloud").tag(ProfileType.icloud)
                #endif
                Text("Remote").tag(ProfileType.remote)
            } label: {
                Text("Type")
            }
            if profileType == .local {
                Picker(selection: $fileImport) {
                    Text("Create New").tag(false)
                    Text("Import").tag(true)
                } label: {
                    Text("File")
                }
                #if os(tvOS)
                .disabled(true)
                #endif
                viewBuilder {
                    if fileImport {
                        HStack {
                            Text("File Path")
                            Spacer()
                            Spacer()
                            if let fileURL {
                                Button(fileURL.fileName) {
                                    pickerPresented = true
                                }
                            } else {
                                Button("Choose") {
                                    pickerPresented = true
                                }
                            }
                        }
                    }
                }
            } else if profileType == .icloud {
                FormItem(String(localized: "Path")) {
                    TextField("Path", text: $remotePath, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
            } else if profileType == .remote {
                FormItem(String(localized: "URL")) {
                    TextField("URL", text: $remotePath, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Auto Update", isOn: $autoUpdate)
                FormItem(String(localized: "Auto Update Interval")) {
                    TextField("Auto Update Interval", text: $autoUpdateInterval.stringBinding(defaultValue: 60), prompt: Text("In Minutes"))
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                }
            }
            Section {
                if !isSaving {
                    FormButton {
                        isSaving = true
                        Task {
                            await createProfile()
                        }
                    } label: {
                        Label("Create", systemImage: "doc.fill.badge.plus")
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("New Profile")
        .alertBinding($alert)
        #if os(iOS) || os(macOS)
            .fileImporter(
                isPresented: $pickerPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    if !urls.isEmpty {
                        fileURL = urls[0]
                    }
                } catch {
                    alert = Alert(error)
                    return
                }
            }
        #endif
    }

    private func createProfile() async {
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

    private func resetFields() {
        profileName = ""
        profileType = .local
        fileImport = false
        fileURL = nil
        remotePath = ""
    }

    private nonisolated func createProfileBackground() async throws {
        let nextProfileID = try await ProfileManager.nextID()

        var savePath = ""
        var remoteURL: String? = nil
        var lastUpdated: Date? = nil

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
                try await UIProfileUpdateTask.configure()
            #else
                try await ProfileUpdateTask.configure()
            #endif
        }
    }
}
