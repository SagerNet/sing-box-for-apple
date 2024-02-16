
import Libbox
import Library
import SwiftUI

public struct CoreView: View {
    @State private var isLoading = true

    @State private var version = ""
    @State private var dataSize = ""

    public init() {}
    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    FormTextItem("Version", version)
                    FormTextItem("Data Size", dataSize)

                    Section("Working Directory") {
                        #if os(macOS)
                            FormButton {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FilePath.workingDirectory.relativePath)
                            } label: {
                                Label("Open", systemImage: "macwindow.and.cursorarrow")
                            }
                        #endif
                        FormButton(role: .destructive) {
                            Task {
                                await destroyWorkingDirectory()
                            }
                        } label: {
                            Label("Destroy", systemImage: "trash.fill")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Core")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private nonisolated func loadSettings() async {
        if ApplicationLibrary.inPreview {
            version = "<redacted>"
            dataSize = LibboxFormatBytes(1000 * 1000 * 10)
            isLoading = false
        } else {
            version = LibboxVersion()
            dataSize = "Loading..."
            isLoading = false
            await loadSettingsBackground()
        }
    }

    private nonisolated func loadSettingsBackground() async {
        let dataSize = (try? FilePath.workingDirectory.formattedSize()) ?? "Unknown"
        await MainActor.run {
            self.dataSize = dataSize
        }
    }

    private nonisolated func destroyWorkingDirectory() async {
        try? FileManager.default.removeItem(at: FilePath.workingDirectory)
        await MainActor.run {
            isLoading = true
        }
    }
}

private extension URL {
    func formattedSize() throws -> String? {
        guard let urls = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil)?.allObjects as? [URL] else {
            return nil
        }
        let size = try urls.lazy.reduce(0) {
            try ($1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) + $0
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        guard let byteCount = formatter.string(for: size) else {
            return nil
        }
        return byteCount
    }
}
