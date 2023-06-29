import Foundation
import Library
import SwiftUI

public struct EditProfileContentView: View {
    #if os(macOS)
        public static let windowID = "edit-profile-content"
    #endif

    public struct Context: Codable, Hashable {
        public let profileID: Int64
        public let readOnly: Bool
    }

    private let profileID: Int64?
    private let readOnly: Bool

    public init(_ context: Context?) {
        profileID = context?.profileID
        readOnly = context?.readOnly == true
    }

    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var profile: Profile!
    @State private var profileContent: String = ""
    @State private var isChanged = false

    @State private var errorPresented = false
    @State private var errorMessage = ""
    @State private var fatalError = false

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        loadContent()
                    }
                }
            } else {
                viewBuilder {
                    if readOnly {
                        TextEditor(text: .constant(profileContent))
                    } else {
                        TextEditor(text: $profileContent)
                    }
                }
                .font(Font.system(.caption2, design: .monospaced))
                .disableAutocorrection(true)
                #if os(iOS)
                    .textInputAutocapitalization(.none)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                #elseif os(macOS)
                    .padding()
                #endif
                    .onChange(of: profileContent) { _ in
                        isChanged = true
                    }
            }
        }
        .alert(isPresented: $errorPresented) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("Ok"), action: {
                    if fatalError {
                        dismiss()
                    }
                })
            )
        }
        .navigationTitle(navigationTitle)
        #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    if !readOnly {
                        Button(action: {
                            Task.detached {
                                saveContent()
                            }
                        }, label: {
                            Image("save", label: Text("Save"))
                        })
                        .disabled(!isChanged)
                    }
                }
            }
        #elseif os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !readOnly {
                        Button("Save") {
                            Task.detached {
                                saveContent()
                            }
                        }.disabled(!isChanged)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var navigationTitle: String {
        if readOnly {
            return "View Content"
        } else {
            return "Edit Content"
        }
    }

    private func loadContent() {
        do {
            try loadContent0()
        } catch {
            errorMessage = error.localizedDescription
            fatalError = true
            errorPresented = true
        }
    }

    private func loadContent0() throws {
        guard let profileID else {
            throw NSError(domain: "Context destroyed", code: 0)
        }
        guard let profile = try ProfileManager.get(profileID) else {
            throw NSError(domain: "Profile missing", code: 0)
        }
        profileContent = try profile.read()
        self.profile = profile
        isLoading = false
    }

    private func saveContent() {
        guard let profile else {
            return
        }
        do {
            try profile.write(profileContent)
        } catch {
            errorMessage = error.localizedDescription
            errorPresented = true
            return
        }
        isChanged = false
    }
}
