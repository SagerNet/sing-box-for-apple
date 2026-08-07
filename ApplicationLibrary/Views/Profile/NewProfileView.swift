import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct NewProfileView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NewProfileViewModel
    private var onSuccess: ((Profile) async -> Void)?

    public struct ImportRequest: Codable, Hashable, Identifiable {
        public var id: String {
            url
        }

        public let name: String
        public let url: String
    }

    public struct LocalImportRequest: Hashable, Identifiable {
        public var id: String {
            fileURL.absoluteString
        }

        public let name: String
        public let fileURL: URL

        public init(name: String, fileURL: URL) {
            self.name = name
            self.fileURL = fileURL
        }
    }

    public init(
        _ importRequest: ImportRequest? = nil,
        localImportRequest: LocalImportRequest? = nil,
        onSuccess: ((Profile) async -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: NewProfileViewModel(importRequest: importRequest, localImportRequest: localImportRequest))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    private static var profileTypeOptions: [FormPickerOption<ProfileType>] {
        var options = [FormPickerOption(ProfileType.local, String(localized: "Local"))]
        #if !os(tvOS)
            options.append(FormPickerOption(ProfileType.icloud, String(localized: "iCloud")))
        #endif
        options.append(FormPickerOption(ProfileType.remote, String(localized: "Remote")))
        return options
    }

    private static var fileImportOptions: [FormPickerOption<Bool>] {
        [
            FormPickerOption(false, String(localized: "Create New")),
            FormPickerOption(true, String(localized: "Import")),
        ]
    }

    private var ownsDismiss: Bool {
        #if os(tvOS)
            onSuccess == nil
        #else
            true
        #endif
    }

    private var formContent: some View {
        FormView {
            Section {
                FormItem(String(localized: "Name")) {
                    TextField("Name", text: $viewModel.profileName, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
                FormPicker(String(localized: "Type"), options: Self.profileTypeOptions, selection: $viewModel.profileType)
                if viewModel.profileType == .local {
                    FormPicker(String(localized: "File"), options: Self.fileImportOptions, selection: $viewModel.fileImport)
                    #if os(tvOS)
                        .disabled(true)
                    #endif
                    Group {
                        if viewModel.fileImport {
                            HStack {
                                Text("File Path")
                                Spacer()
                                Spacer()
                                if let fileURL = viewModel.fileURL {
                                    Button(fileURL.fileName) {
                                        viewModel.pickerPresented = true
                                    }
                                } else {
                                    Button("Choose") {
                                        viewModel.pickerPresented = true
                                    }
                                }
                            }
                        }
                    }
                } else if viewModel.profileType == .icloud {
                    FormItem(String(localized: "Path")) {
                        TextField("Path", text: $viewModel.remotePath, prompt: Text("Required"))
                            .multilineTextAlignment(.trailing)
                    }
                } else if viewModel.profileType == .remote {
                    FormItem(String(localized: "URL")) {
                        TextField("URL", text: $viewModel.remotePath, prompt: Text("Required"))
                            .multilineTextAlignment(.trailing)
                        #if !os(macOS)
                            .keyboardType(.URL)
                        #endif
                    }
                    Toggle("Auto Update", isOn: $viewModel.autoUpdate)
                    FormItem(String(localized: "Auto Update Interval")) {
                        TextField("Auto Update Interval", text: $viewModel.autoUpdateInterval.stringBinding(defaultValue: 60), prompt: Text("In Minutes"))
                            .multilineTextAlignment(.trailing)
                        #if !os(macOS)
                            .keyboardType(.numberPad)
                        #endif
                    }
                }
            } footer: {
                if viewModel.profileType == .icloud {
                    let fileName = viewModel.remotePath.isEmpty ? String(localized: "FileName") : viewModel.remotePath
                    Text("File will be located at iCloud Drive/sing-box/\(fileName)")
                }
            }
            #if os(iOS) || os(tvOS)
                Section {
                    if !viewModel.isSaving {
                        FormButton {
                            viewModel.isSaving = true
                            Task {
                                await viewModel.createProfile(
                                    environments: environments,
                                    dismiss: ownsDismiss ? dismiss : nil,
                                    onSuccess: onSuccess
                                )
                            }
                        } label: {
                            Label("Create", systemImage: "doc.fill.badge.plus")
                        }
                    } else {
                        ProgressView()
                    }
                }
            #endif
        }
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.isImport ? "Import Profile" : "New Profile")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                formContent
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            viewModel.isSaving = true
                            Task {
                                await viewModel.createProfile(
                                    environments: environments,
                                    dismiss: dismiss,
                                    onSuccess: onSuccess
                                )
                            }
                        }
                    }
                }
            }
            .disabled(viewModel.isSaving)
            .alert($viewModel.alert)
            .fileImporter(
                isPresented: $viewModel.pickerPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    if !urls.isEmpty {
                        viewModel.fileURL = urls[0]
                    }
                } catch {
                    viewModel.alert = AlertState(action: "read imported profile file", error: error)
                    return
                }
            }
        }
    #else
        private var iOSBody: some View {
            formContent
                .navigationTitle("New Profile")
                .disabled(viewModel.isSaving)
                .alert($viewModel.alert)
                .onChangeCompat(of: viewModel.createSucceeded) { newValue in
                    if newValue, ownsDismiss {
                        dismiss()
                    }
                }
            #if os(iOS)
                .fileImporter(
                    isPresented: $viewModel.pickerPresented,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    do {
                        let urls = try result.get()
                        if !urls.isEmpty {
                            viewModel.fileURL = urls[0]
                        }
                    } catch {
                        viewModel.alert = AlertState(action: "read imported profile file", error: error)
                        return
                    }
                }
            #endif
        }
    #endif
}
