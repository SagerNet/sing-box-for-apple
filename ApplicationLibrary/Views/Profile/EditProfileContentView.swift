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

        public var body: some View {
            viewBuilder {
                if viewModel.isLoading {
                    ProgressView().onAppear {
                        Task {
                            await viewModel.loadContent()
                        }
                    }
                } else {
                    #if os(iOS)
                        RunestoneTextView(
                            text: readOnly ? .constant(viewModel.profileContent) : $viewModel.profileContent,
                            isEditable: !readOnly
                        )
                        .onChangeCompat(of: viewModel.profileContent) {
                            viewModel.markAsChanged()
                        }
                    #elseif os(macOS)
                        viewBuilder {
                            if readOnly {
                                TextEditor(text: .constant(viewModel.profileContent))
                            } else {
                                TextEditor(text: $viewModel.profileContent)
                            }
                        }
                        .font(Font.system(.caption2, design: .monospaced))
                        .autocorrectionDisabled(true)
                        .textContentType(.init(rawValue: ""))
                        .padding()
                        .onChangeCompat(of: viewModel.profileContent) {
                            viewModel.markAsChanged()
                        }
                    #endif
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
    }

#endif
