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
        public var id: String { url }
        public let name: String
        public let url: String
    }

    public init(
        _ importRequest: ImportRequest? = nil,
        onSuccess: ((Profile) async -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: NewProfileViewModel(importRequest: importRequest))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        FormView {
            FormItem(String(localized: "Name")) {
                TextField("Name", text: $viewModel.profileName, prompt: Text("Required"))
                    .multilineTextAlignment(.trailing)
            }
            Picker(selection: $viewModel.profileType) {
                #if !os(tvOS)
                    Text("Local").tag(ProfileType.local)
                    Text("iCloud").tag(ProfileType.icloud)
                #endif
                Text("Remote").tag(ProfileType.remote)
            } label: {
                Text("Type")
            }
            if viewModel.profileType == .local {
                Picker(selection: $viewModel.fileImport) {
                    Text("Create New").tag(false)
                    Text("Import").tag(true)
                } label: {
                    Text("File")
                }
                #if os(tvOS)
                .disabled(true)
                #endif
                viewBuilder {
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
                    #if !os(macOS)
                        .keyboardType(.asciiCapableNumberPad)
                    #endif
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
            #if os(iOS) || os(tvOS)
                Section {
                    if !viewModel.isSaving {
                        FormButton {
                            viewModel.isSaving = true
                            Task {
                                await viewModel.createProfile(
                                    environments: environments,
                                    dismiss: onSuccess == nil ? dismiss : nil,
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
        .navigationTitle("New Profile")
        #if os(macOS)
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
                                    dismiss: onSuccess == nil ? dismiss : nil,
                                    onSuccess: onSuccess
                                )
                            }
                        }
                    }
                }
            }
        #endif
            .disabled(viewModel.isSaving)
            .alertBinding($viewModel.alert)
        #if os(iOS) || os(macOS)
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
                    viewModel.alert = Alert(error)
                    return
                }
            }
        #endif
    }
}
