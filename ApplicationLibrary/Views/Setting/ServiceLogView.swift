import Foundation
import Library
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct ServiceLogView: View {
    #if os(macOS)
        public static let windowID = "service-log"
    #endif

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var content = ""
    @State private var fileExporterPresented = false
    private let logFont = Font.system(.caption, design: .monospaced)

    public init() {}

    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadContent()
                    }
                }
            } else {
                if content.isEmpty {
                    Text("Empty content")
                } else {
                    ScrollView {
                        Text(content)
                            .font(logFont)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding()
                }
            }
        }
        #if !os(tvOS)
        .toolbar {
            if !content.isEmpty {
                Button("Export") {
                    fileExporterPresented = true
                }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteContent()
                    }
                }
            }
        }
        #endif
        #if !os(tvOS)
        .fileExporter(
            isPresented: $fileExporterPresented,
            document: LogDocument(content),
            contentType: .text,
            defaultFilename: "service-log.txt",
            onCompletion: { _ in }
        )
        #endif
        .navigationTitle("Service Log")
        #if os(tvOS)
            .focusable()
        #endif
    }

    private nonisolated func loadContent() async {
        var content = ""
        do {
            content = try String(contentsOf: FilePath.cacheDirectory.appendingPathComponent("stderr.log"))
        } catch {}
        if content.isEmpty {
            do {
                content = try String(contentsOf: FilePath.cacheDirectory.appendingPathComponent("stderr.log.old"))
            } catch {}
        }
        await MainActor.run { [content] in
            self.content = content
            isLoading = false
        }
    }

    private nonisolated func deleteContent() async {
        try? FileManager.default.removeItem(at: FilePath.cacheDirectory.appendingPathComponent("stderr.log"))
        try? FileManager.default.removeItem(at: FilePath.cacheDirectory.appendingPathComponent("stderr.log.old"))
        await MainActor.run {
            dismiss()
            isLoading = true
        }
    }

    #if !os(tvOS)
        private struct LogDocument: FileDocument {
            static var readableContentTypes = [UTType.text]

            let content: String

            init(_ content: String) {
                self.content = content
            }

            init(configuration: ReadConfiguration) throws {
                if let data = configuration.file.regularFileContents {
                    content = String(decoding: data, as: UTF8.self)
                } else {
                    content = ""
                }
            }

            func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
                FileWrapper(regularFileWithContents: Data(content.utf8))
            }
        }
    #endif
}
