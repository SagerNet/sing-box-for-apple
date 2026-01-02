import FileProvider
import UniformTypeIdentifiers

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain

    private static let appGroupID: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else {
            fatalError("Missing AppGroupIdentifier in Info.plist")
        }
        return value
    }()

    private var workingDirectory: URL {
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)!
        return groupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("Working", isDirectory: true)
    }

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    func invalidate() {}

    // MARK: - NSFileProviderReplicatedExtension

    func item(for identifier: NSFileProviderItemIdentifier,
              request _: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress
    {
        let progress = Progress(totalUnitCount: 1)

        if identifier == .rootContainer {
            completionHandler(FileProviderItem(rootAt: workingDirectory), nil)
        } else {
            let url = fileURL(for: identifier)
            if FileManager.default.fileExists(atPath: url.path) {
                completionHandler(FileProviderItem(url: url, identifier: identifier, workingDirectory: workingDirectory), nil)
            } else {
                completionHandler(nil, NSFileProviderError(.noSuchItem))
            }
        }

        progress.completedUnitCount = 1
        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version _: NSFileProviderItemVersion?,
                       request _: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress
    {
        let progress = Progress(totalUnitCount: 100)

        let url = fileURL(for: itemIdentifier)
        guard FileManager.default.fileExists(atPath: url.path) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }

        let item = FileProviderItem(url: url, identifier: itemIdentifier, workingDirectory: workingDirectory)
        completionHandler(url, item, nil)
        progress.completedUnitCount = 100

        return progress
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields _: NSFileProviderItemFields,
                    contents url: URL?,
                    options _: NSFileProviderCreateItemOptions,
                    request _: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress
    {
        let progress = Progress(totalUnitCount: 100)

        let parentURL = fileURL(for: itemTemplate.parentItemIdentifier)
        let targetURL = parentURL.appendingPathComponent(itemTemplate.filename)

        do {
            if let contentType = itemTemplate.contentType, contentType.conforms(to: .folder) {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else if let sourceURL = url {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            } else {
                FileManager.default.createFile(atPath: targetURL.path, contents: nil)
            }

            let identifier = itemIdentifier(for: targetURL)
            let item = FileProviderItem(url: targetURL, identifier: identifier, workingDirectory: workingDirectory)
            completionHandler(item, [], false, nil)

        } catch {
            completionHandler(nil, [], false, error)
        }

        progress.completedUnitCount = 100
        return progress
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion _: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options _: NSFileProviderModifyItemOptions,
                    request _: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress
    {
        let progress = Progress(totalUnitCount: 100)

        var currentURL = fileURL(for: item.itemIdentifier)
        var newIdentifier = item.itemIdentifier

        do {
            if changedFields.contains(.filename) {
                let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(item.filename)
                if currentURL != newURL {
                    try FileManager.default.moveItem(at: currentURL, to: newURL)
                    currentURL = newURL
                    newIdentifier = itemIdentifier(for: newURL)
                }
            }

            if changedFields.contains(.parentItemIdentifier) {
                let newParentURL = fileURL(for: item.parentItemIdentifier)
                let newURL = newParentURL.appendingPathComponent(currentURL.lastPathComponent)
                if currentURL != newURL {
                    try FileManager.default.moveItem(at: currentURL, to: newURL)
                    currentURL = newURL
                    newIdentifier = itemIdentifier(for: newURL)
                }
            }

            if changedFields.contains(.contents), let contentsURL = newContents {
                try FileManager.default.removeItem(at: currentURL)
                try FileManager.default.copyItem(at: contentsURL, to: currentURL)
            }

            let resultItem = FileProviderItem(url: currentURL, identifier: newIdentifier, workingDirectory: workingDirectory)
            completionHandler(resultItem, [], false, nil)

        } catch {
            completionHandler(nil, [], false, error)
        }

        progress.completedUnitCount = 100
        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion _: NSFileProviderItemVersion,
                    options _: NSFileProviderDeleteItemOptions,
                    request _: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress
    {
        let progress = Progress(totalUnitCount: 1)

        let url = fileURL(for: identifier)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }

        progress.completedUnitCount = 1
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request _: NSFileProviderRequest) throws -> NSFileProviderEnumerator
    {
        if containerItemIdentifier == .workingSet {
            return FileProviderEnumerator(workingSet: true, workingDirectory: workingDirectory)
        }

        if containerItemIdentifier == .trashContainer {
            throw NSFileProviderError(.noSuchItem)
        }

        let url: URL
        if containerItemIdentifier == .rootContainer {
            url = workingDirectory
        } else {
            url = fileURL(for: containerItemIdentifier)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSFileProviderError(.noSuchItem)
        }

        return FileProviderEnumerator(url: url, workingDirectory: workingDirectory)
    }

    // MARK: - Helper Methods

    private func fileURL(for identifier: NSFileProviderItemIdentifier) -> URL {
        if identifier == .rootContainer {
            return workingDirectory
        }
        let relativePath = identifier.rawValue
        return workingDirectory.appendingPathComponent(relativePath)
    }

    private func itemIdentifier(for url: URL) -> NSFileProviderItemIdentifier {
        let relativePath = url.path.replacingOccurrences(of: workingDirectory.path + "/", with: "")
        if relativePath == url.path || relativePath.isEmpty {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(relativePath)
    }
}
