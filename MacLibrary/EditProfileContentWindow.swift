import ApplicationLibrary
import Library
import SwiftUI

struct EditProfileContentWindow: View {
    let context: EditProfileContentView.Context?

    @StateObject private var viewModel: EditProfileContentViewModel
    @State private var showDiscardAlert = false
    @State private var windowState = WindowState()

    private let readOnly: Bool

    init(context: EditProfileContentView.Context?) {
        self.context = context
        readOnly = context?.readOnly == true
        _viewModel = StateObject(wrappedValue: EditProfileContentViewModel(profileID: context?.profileID))
    }

    @Environment(\.profileEditor) private var profileEditor

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await viewModel.loadContent()
                    }
            } else {
                editorView
                    .onChangeCompat(of: viewModel.profileContent) {
                        viewModel.markAsChanged()
                    }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(WindowAccessor { window in
            guard let window else { return }
            if windowState.window == nil {
                windowState.window = window
                windowState.onClose = { [weak viewModel] in
                    viewModel?.reset()
                }
                let delegate = WindowCloseDelegate(
                    windowState: windowState,
                    hasUnsavedChanges: { [weak viewModel] in
                        viewModel?.isChanged == true
                    },
                    showAlert: {
                        showDiscardAlert = true
                    }
                )
                windowState.delegate = delegate
                window.delegate = delegate
            }
        })
        .onExitCommand {
            handleClose()
        }
        .alert("Unsaved Changes", isPresented: $showDiscardAlert) {
            Button("Don't Save", role: .destructive) {
                windowState.forceClose()
            }
            Button("Cancel", role: .cancel) {}
            if !readOnly {
                Button("Save") {
                    Task {
                        await viewModel.saveContent()
                        if viewModel.alert == nil {
                            windowState.forceClose()
                        }
                    }
                }
            }
        } message: {
            Text("Do you want to save the changes you made?")
        }
        .alertBinding($viewModel.alert)
        .navigationTitle(navigationTitle)
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
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!viewModel.isChanged)
                } else {
                    Button {
                        NSPasteboard.general.setString(viewModel.profileContent, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .textContentType(.init(rawValue: ""))
        .padding()
    }

    private func handleClose() {
        if viewModel.isChanged, !readOnly {
            showDiscardAlert = true
        } else {
            windowState.forceClose()
        }
    }
}

private class WindowState {
    weak var window: NSWindow?
    var delegate: WindowCloseDelegate?
    var onClose: (() -> Void)?

    func forceClose() {
        delegate?.allowClose = true
        window?.close()
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            callback(view.window)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    var allowClose = false
    private let windowState: WindowState
    private let hasUnsavedChanges: () -> Bool
    private let showAlert: () -> Void

    init(windowState: WindowState, hasUnsavedChanges: @escaping () -> Bool, showAlert: @escaping () -> Void) {
        self.windowState = windowState
        self.hasUnsavedChanges = hasUnsavedChanges
        self.showAlert = showAlert
        super.init()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if allowClose {
            return true
        }
        if hasUnsavedChanges() {
            DispatchQueue.main.async {
                self.showAlert()
            }
            return false
        }
        return true
    }

    func windowWillClose(_: Notification) {
        windowState.onClose?()
        allowClose = false
    }
}
