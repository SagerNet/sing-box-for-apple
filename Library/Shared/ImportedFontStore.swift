#if os(iOS)
    import CoreText
    import Foundation
    import SwiftUI

    @MainActor
    public final class ImportedFontStore: ObservableObject {
        public static let shared = ImportedFontStore()

        @Published public private(set) var fonts: [ImportedFont] = []

        private let directory: URL
        private let queue = DispatchQueue(label: "io.nekohasekai.sing-box.imported-fonts", qos: .userInitiated)
        private var bootstrapTask: Task<Void, Never>?

        private init() {
            directory = FilePath.sharedDirectory.appendingPathComponent("fonts", isDirectory: true)
        }

        public func bootstrap() async {
            if let bootstrapTask {
                await bootstrapTask.value
                return
            }
            let task = Task<Void, Never> {
                try? await update { directory in
                    Self.registerAll(in: directory)
                    return Self.scan(in: directory)
                }
            }
            bootstrapTask = task
            await task.value
        }

        public func importFile(from sourceURL: URL) async throws {
            await bootstrap()
            try await update { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = try sourceURL.withRequiredSecurityScopedAccess(
                    or: NSError(domain: "ImportedFontStore", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing access to selected file")])
                ) {
                    let data = try Data(contentsOf: sourceURL)
                    let destination = Self.uniqueDestination(in: directory, basedOn: sourceURL)
                    try data.write(to: destination, options: .atomic)
                    return destination
                }
                var error: Unmanaged<CFError>?
                guard CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error) else {
                    try? FileManager.default.removeItem(at: destination)
                    if let error {
                        throw error.takeRetainedValue() as Error
                    }
                    throw NSError(domain: "ImportedFontStore", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "File is not a valid font")])
                }
                return Self.scan(in: directory)
            }
        }

        public func delete(_ font: ImportedFont) async throws {
            await bootstrap()
            try await update { directory in
                _ = CTFontManagerUnregisterFontsForURL(font.fileURL as CFURL, .process, nil)
                do {
                    try FileManager.default.removeItem(at: font.fileURL)
                } catch {
                    _ = CTFontManagerRegisterFontsForURL(font.fileURL as CFURL, .process, nil)
                    throw error
                }
                return Self.scan(in: directory)
            }
            let currentFamily = await SharedPreferences.tailscaleSSHTerminalFontFamily.get()
            if currentFamily == font.familyName {
                await SharedPreferences.tailscaleSSHTerminalFontFamily.set("")
            }
        }

        private func update(_ operation: @escaping @Sendable (URL) throws -> [ImportedFont]) async throws {
            let directory = directory
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async {
                    let result = Result { try operation(directory) }
                    DispatchQueue.main.async {
                        switch result {
                        case let .success(fonts):
                            self.fonts = fonts
                            continuation.resume()
                        case let .failure(error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }

        private nonisolated static func registerAll(in directory: URL) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for url in contents(of: directory) {
                _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        private nonisolated static func scan(in directory: URL) -> [ImportedFont] {
            contents(of: directory)
                .compactMap { url -> ImportedFont? in
                    guard let familyName = familyName(for: url) else { return nil }
                    return ImportedFont(fileURL: url, familyName: familyName)
                }
                .sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
        }

        private nonisolated static func contents(of directory: URL) -> [URL] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return urls.filter(isSupportedFont)
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
        public var id: URL {
            fileURL
        }

        public let fileURL: URL
        public let familyName: String
    }
#endif
