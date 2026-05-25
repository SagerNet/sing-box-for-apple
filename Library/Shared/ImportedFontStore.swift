#if os(iOS)
    import CoreText
    import Foundation
    import SwiftUI

    @MainActor
    public final class ImportedFontStore: ObservableObject {
        public static let shared = ImportedFontStore()

        @Published public private(set) var fonts: [ImportedFont] = []

        private let directory: URL

        private init() {
            directory = FilePath.sharedDirectory.appendingPathComponent("fonts", isDirectory: true)
        }

        public func bootstrap() {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in urls where Self.isSupportedFont(url) {
                _ = register(url)
            }
            refresh()
        }

        public func importFile(from sourceURL: URL) async throws {
            let targetDirectory = directory
            let destination = try await BlockingIO.run {
                try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
                return try sourceURL.withRequiredSecurityScopedAccess(
                    or: NSError(domain: "ImportedFontStore", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing access to selected file")])
                ) {
                    let data = try Data(contentsOf: sourceURL)
                    let destinationURL = Self.uniqueDestination(in: targetDirectory, basedOn: sourceURL)
                    try data.write(to: destinationURL, options: .atomic)
                    return destinationURL
                }
            }
            guard register(destination) else {
                try? FileManager.default.removeItem(at: destination)
                throw NSError(domain: "ImportedFontStore", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "File is not a valid font")])
            }
            refresh()
        }

        public func delete(_ font: ImportedFont) async throws {
            unregister(font.fileURL)
            let url = font.fileURL
            try await BlockingIO.run {
                try FileManager.default.removeItem(at: url)
            }
            let currentFamily = await SharedPreferences.tailscaleSSHTerminalFontFamily.get()
            if currentFamily == font.familyName {
                await SharedPreferences.tailscaleSSHTerminalFontFamily.set("")
            }
            refresh()
        }

        @discardableResult
        private func register(_ url: URL) -> Bool {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        private func unregister(_ url: URL) {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }

        private func refresh() {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let entries = urls.compactMap { url -> ImportedFont? in
                guard Self.isSupportedFont(url) else { return nil }
                guard let familyName = Self.familyName(for: url) else { return nil }
                return ImportedFont(fileURL: url, familyName: familyName)
            }
            fonts = entries.sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
        }

        private nonisolated static func isSupportedFont(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ext == "ttf" || ext == "otf" || ext == "ttc" || ext == "otc"
        }

        private nonisolated static func familyName(for url: URL) -> String? {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            else { return nil }
            return name
        }

        private nonisolated static func uniqueDestination(in directory: URL, basedOn sourceURL: URL) -> URL {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
            var counter = 1
            while FileManager.default.fileExists(atPath: candidate.path) {
                let nextName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                candidate = directory.appendingPathComponent(nextName)
                counter += 1
            }
            return candidate
        }
    }

    public struct ImportedFont: Identifiable, Hashable, Sendable {
        public var id: URL { fileURL }
        public let fileURL: URL
        public let familyName: String
    }
#endif
