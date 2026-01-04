import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {
    private let url: URL
    private let fileAttributes: [FileAttributeKey: Any]
    private let _identifier: NSFileProviderItemIdentifier
    private let _parentIdentifier: NSFileProviderItemIdentifier
    private let isRoot: Bool

    init(rootAt url: URL) {
        self.url = url
        _identifier = .rootContainer
        _parentIdentifier = .rootContainer
        isRoot = true
        fileAttributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        super.init()
    }

    init(url: URL, identifier: NSFileProviderItemIdentifier, workingDirectory: URL) {
        self.url = url
        _identifier = identifier
        isRoot = false
        fileAttributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]

        let parentPath = url.deletingLastPathComponent().path
        if parentPath == workingDirectory.path {
            _parentIdentifier = .rootContainer
        } else {
            let relativePath = parentPath.replacingOccurrences(of: workingDirectory.path + "/", with: "")
            _parentIdentifier = NSFileProviderItemIdentifier(relativePath)
        }

        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        _identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        _parentIdentifier
    }

    var filename: String {
        if isRoot {
            return "sing-box"
        }
        return url.lastPathComponent
    }

    var contentType: UTType {
        if isDirectory {
            return .folder
        }
        return UTType(filenameExtension: url.pathExtension) ?? .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        [
            .allowsReading,
            .allowsWriting,
            .allowsRenaming,
            .allowsReparenting,
            .allowsDeleting,
            .allowsAddingSubItems,
            .allowsContentEnumerating,
        ]
    }

    var itemVersion: NSFileProviderItemVersion {
        let modDate = fileAttributes[.modificationDate] as? Date ?? Date()
        let contentVersion = withUnsafeBytes(of: modDate.timeIntervalSince1970) { Data($0) }
        return NSFileProviderItemVersion(contentVersion: contentVersion, metadataVersion: contentVersion)
    }

    var documentSize: NSNumber? {
        guard !isDirectory else { return nil }
        return fileAttributes[.size] as? NSNumber
    }

    var creationDate: Date? {
        fileAttributes[.creationDate] as? Date
    }

    var contentModificationDate: Date? {
        fileAttributes[.modificationDate] as? Date
    }

    var childItemCount: NSNumber? {
        guard isDirectory else { return nil }
        let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        return NSNumber(value: contents?.count ?? 0)
    }

    // MARK: - Local File Status

    var isUploaded: Bool { true }
    var isUploading: Bool { false }
    var isDownloaded: Bool { true }
    var isDownloading: Bool { false }
    var isMostRecentVersionDownloaded: Bool { true }

    private var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
