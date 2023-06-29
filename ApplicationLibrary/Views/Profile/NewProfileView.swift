import Foundation
import Libbox
import Library
import SwiftUI

public struct NewProfileView: View {
    #if os(macOS)
        public static let windowID = "new-profile"
    #endif

    @Environment(\.dismiss) private var dismiss

    @State private var isSaving = false
    @State private var profileName = ""
    @State private var profileType = ProfileType.local
    @State private var fileImport = false
    @State private var fileURL: URL!
    @State private var remotePath = ""
    @State private var pickerPresented = false
    @State private var errorPresented = false
    @State private var errorMessage = ""

    private let callback: (() -> Void)?
    public init(_ callback: (() -> Void)? = nil) {
        self.callback = callback
    }

    public var body: some View {
        FormView {
            FormItem("Name") {
                TextField("Name", text: $profileName, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
            }
            Picker(selection: $profileType) {
                Text("Local").tag(ProfileType.local)
                Text("iCloud").tag(ProfileType.icloud)
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
                FormItem("Path") {
                    TextField("Path", text: $remotePath, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
            } else if profileType == .remote {
                FormItem("URL") {
                    TextField("URL", text: $remotePath, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
            }
            Section {
                if !isSaving {
                    Button("Create") {
                        isSaving = true
                        Task.detached {
                            await createProfile()
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("New Profile")
        .alert(isPresented: $errorPresented) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Ok"))
            )
        }
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
                errorMessage = error.localizedDescription
                errorPresented = true
                return
            }
        }
    }

    private func createProfile() async {
        defer {
            isSaving = false
        }
        if profileName.isEmpty {
            errorMessage = "Missing profile name"
            errorPresented = true
            return
        }
        if remotePath.isEmpty {
            if profileType == .icloud {
                errorMessage = "Missing path"
                errorPresented = true
                return
            } else if profileType == .remote {
                errorMessage = "Missing URL"
                errorPresented = true
                return
            }
        }
        do {
            try createProfile0()
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
            return
        }
        await MainActor.run {
            dismiss()
            if let callback {
                callback()
            }
            #if os(macOS)
                NotificationCenter.default.post(name: ProfileView.notificationName, object: nil)
                resetFields()
            #endif
        }
    }

    private func resetFields() {
        profileName = ""
        profileType = .local
        fileImport = false
        fileURL = nil
        remotePath = ""
    }

    private func createProfile0() throws {
        let nextProfileID = try ProfileManager.nextID()

        var savePath = ""
        var remoteURL: String? = nil

        if profileType == .local {
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            if fileImport {
                guard let fileURL else {
                    errorMessage = "Missing file"
                    errorPresented = true
                    return
                }
                if !fileURL.startAccessingSecurityScopedResource() {
                    errorMessage = "Missing access to selected file"
                    errorPresented = true
                    return
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
        }
        try ProfileManager.create(Profile(name: profileName, type: profileType, path: savePath, remoteURL: remoteURL))
    }
}
