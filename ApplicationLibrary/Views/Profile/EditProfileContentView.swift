#if os(iOS) || os(macOS)
    import Foundation
    import Library
    import SwiftUI

    @MainActor
    public struct EditProfileContentView: View {
        public struct Context: Codable, Hashable {
            public let profileID: Int64
            public let readOnly: Bool
        }

        private let readOnly: Bool
        @StateObject private var viewModel: EditProfileContentViewModel

        public init(_ context: Context?) {
            readOnly = context?.readOnly == true
            _viewModel = StateObject(wrappedValue: EditProfileContentViewModel(profileID: context?.profileID))
        }

        @Environment(\.dismiss) private var dismiss
        @Environment(\.profileEditor) private var profileEditor

        public var body: some View {
            Group {
                if viewModel.isLoading {
                    ProgressView().onAppear {
                        Task {
                            await viewModel.loadContent()
                        }
                    }
                } else {
                    editorView
                        .onChangeCompat(of: viewModel.profileContent) {
                            viewModel.markAsChanged()
                        }
                }
            }
            .alertBinding($viewModel.alert)
            .navigationTitle(navigationTitle)
            #if os(macOS)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        if !readOnly {
                            Button {
                                Task {
                                    await viewModel.saveContent()
                                }
                            } label: {
                                Label("Save", image: "save")
                            }
                            .disabled(!viewModel.isChanged)
                        } else {
                            Button {
                                NSPasteboard.general.setString(viewModel.profileContent, forType: .fileContents)
                            } label: {
                                Label("Copy", systemImage: "clipboard.fill")
                            }
                        }
                    }
                }
            #elseif os(iOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !readOnly {
                            Button("Save") {
                                Task {
                                    await viewModel.saveContent()
                                }
                            }.disabled(!viewModel.isChanged)
                        } else {
                            Button("Copy") {
                                UIPasteboard.general.string = viewModel.profileContent
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        private var navigationTitle: String {
            if readOnly {
                return String(localized: "View Content")
            } else {
                return String(localized: "Edit Content")
            }
        }

        @ViewBuilder
        private var editorView: some View {
            if let profileEditor {
                profileEditor(
                    readOnly ? .constant(viewModel.profileContent) : $viewModel.profileContent,
                    !readOnly
                )
                #if os(macOS)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
            } else {
                defaultEditorView
            }
        }

        @ViewBuilder
        private var defaultEditorView: some View {
            Group {
                if readOnly {
                    TextEditor(text: .constant(viewModel.profileContent))
                } else {
                    TextEditor(text: $viewModel.profileContent)
                }
            }
            .font(Font.system(.caption2, design: .monospaced))
            .autocorrectionDisabled(true)
            #if os(macOS)
                .textContentType(.init(rawValue: ""))
                .padding()
            #endif
        }
    }

#endif
