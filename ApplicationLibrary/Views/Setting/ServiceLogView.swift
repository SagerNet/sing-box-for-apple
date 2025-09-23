import Foundation
import Library
import SwiftUI

@MainActor
public struct ServiceLogView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var content = ""
    @State private var alert: Alert?

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
        .toolbar {
            if !content.isEmpty {
                #if !os(tvOS)
                    ShareButtonCompat($alert) {
                        Label("Export", systemImage: "square.and.arrow.up.fill")
                    } itemURL: {
                        try content.generateShareFile(name: "service.log")
                    }
                #endif
                Button(role: .destructive) {
                    Task {
                        await deleteContent()
                    }
                } label: {
                    #if !os(tvOS)
                        Label("Delete", systemImage: "trash.fill")
                    #else
                        Image(systemName: "trash.fill")
                            .tint(.red)
                    #endif
                }
            }
        }
        .alertBinding($alert)
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
        #if DEBUG
            if content.isEmpty {
                content = "Empty content"
            }
        #endif
        if !content.isEmpty {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let machineName = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            var deviceInfo = String("Machine: ") + machineName + "\n"
            #if os(iOS)
                await deviceInfo += String("System: ") + (UIDevice.current.systemName) + " " + (UIDevice.current.systemVersion) + "\n"
            #elseif os(macOS)
                deviceInfo += String("System: ") + "macOS " + ProcessInfo().operatingSystemVersionString + "\n"
            #endif
            content = deviceInfo + "\n" + content
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
}
