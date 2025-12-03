import Foundation
import Libbox
import Library
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct NewProfileMenuView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss
    @State private var alert: AlertState?
    @State private var showFileImporter = false
    @State private var importRequest: NewProfileView.ImportRequest?
    @State private var localImportRequest: NewProfileView.LocalImportRequest?
    #if os(iOS)
        @State private var showQRScanner = false
    #elseif os(tvOS)
        @State private var importCompleted = false
    #elseif os(macOS)
        @State private var showNewProfile = false
    #endif

    public init() {}

    public var body: some View {
        #if os(macOS)
            macOSBody
        #else
            otherBody
        #endif
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("New Profile")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                menuContent
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .alert($alert)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.profile, .json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showNewProfile) {
                NewProfileView(onSuccess: { _ in
                    dismiss()
                })
                .environmentObject(environments)
            }
            .sheet(item: $localImportRequest) { request in
                NewProfileView(localImportRequest: request, onSuccess: { _ in
                    dismiss()
                })
                .environmentObject(environments)
            }
        }
    #endif

    private var otherBody: some View {
        Group {
            if let request = importRequest {
                NewProfileView(request)
                    .environmentObject(environments)
            } else if let request = localImportRequest {
                NewProfileView(localImportRequest: request)
                    .environmentObject(environments)
            } else {
                menuContent
            }
        }
        .navigationTitle("New Profile")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .alert($alert)
        #if os(tvOS)
            .onChange(of: importCompleted) { newValue in
                if newValue {
                    dismiss()
                }
            }
        #else
            .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.profile, .json],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImport(result)
                }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView { remoteProfile in
                importRequest = NewProfileView.ImportRequest(name: remoteProfile.name, url: remoteProfile.url)
            }
        }
        #endif
    }

    private var menuContent: some View {
        FormView {
            Section {
                #if os(tvOS)
                    FormNavigationLink {
                        ImportProfileView(onComplete: {
                            importCompleted = true
                        })
                        .environmentObject(environments)
                    } label: {
                        Label("Import from iPhone or iPad", systemImage: "iphone.and.arrow.forward")
                    }
                #endif

                #if !os(tvOS)
                    FormButton {
                        showFileImporter = true
                    } label: {
                        Label("Import from File", systemImage: "doc.badge.plus")
                    }
                #endif

                #if os(iOS)
                    FormButton {
                        showQRScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                #endif

                #if os(macOS)
                    FormButton {
                        showNewProfile = true
                    } label: {
                        Label("Create Manually", systemImage: "square.and.pencil")
                    }
                #else
                    FormNavigationLink {
                        NewProfileView()
                            .environmentObject(environments)
                    } label: {
                        Label("Create Manually", systemImage: "square.and.pencil")
                    }
                #endif
            }
        }
    }

    #if !os(tvOS)
        private func handleFileImport(_ result: Result<[URL], Error>) {
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }

                if url.pathExtension.lowercased() == "json" {
                    let fileName = url.deletingPathExtension().lastPathComponent
                    localImportRequest = NewProfileView.LocalImportRequest(name: fileName, fileURL: url)
                } else {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }

                    let content = try LibboxProfileContent.from(Data(contentsOf: url))

                    alert = AlertState(
                        title: String(localized: "Import Profile"),
                        message: String(localized: "Are you sure to import profile \(content.name)?"),
                        primaryButton: .default(String(localized: "Import")) {
                            Task {
                                do {
                                    try await content.importProfile()
                                    environments.profileUpdate.send()
                                    dismiss()
                                } catch {
                                    alert = AlertState(error: error)
                                }
                            }
                        },
                        secondaryButton: .cancel()
                    )
                }
            } catch {
                alert = AlertState(error: error)
            }
        }
    #endif
}
