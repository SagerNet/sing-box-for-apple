import FileProvider

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let directoryURL: URL?
    private let workingDirectory: URL
    private let isWorkingSet: Bool

    init(url: URL, workingDirectory: URL) {
        directoryURL = url
        self.workingDirectory = workingDirectory
        isWorkingSet = false
        super.init()
    }

    init(workingSet: Bool, workingDirectory: URL) {
        directoryURL = nil
        self.workingDirectory = workingDirectory
        isWorkingSet = workingSet
        super.init()
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt _: NSFileProviderPage) {
        guard !isWorkingSet else {
            var allItems: [FileProviderItem] = []
            enumerateRecursively(at: workingDirectory, into: &allItems)
            observer.didEnumerate(allItems)
            observer.finishEnumerating(upTo: nil)
            return
        }

        guard let url = directoryURL else {
            observer.finishEnumerating(upTo: nil)
            return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let items: [FileProviderItem] = contents.map { childURL in
            let identifier = itemIdentifier(for: childURL)
            return FileProviderItem(url: childURL, identifier: identifier, workingDirectory: workingDirectory)
        }

        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from _: NSFileProviderSyncAnchor) {
        var allItems: [FileProviderItem] = []

        if isWorkingSet {
            enumerateRecursively(at: workingDirectory, into: &allItems)
        } else if let url = directoryURL {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            allItems = contents.map { childURL in
                let identifier = itemIdentifier(for: childURL)
                return FileProviderItem(url: childURL, identifier: identifier, workingDirectory: workingDirectory)
            }
        }

        observer.didUpdate(allItems)
        observer.finishEnumeratingChanges(upTo: currentSyncAnchor(), moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(currentSyncAnchor())
    }

    // MARK: - Helpers

    private func currentSyncAnchor() -> NSFileProviderSyncAnchor {
        let timestamp = Date().timeIntervalSince1970
        return NSFileProviderSyncAnchor(withUnsafeBytes(of: timestamp) { Data($0) })
    }

    private func itemIdentifier(for url: URL) -> NSFileProviderItemIdentifier {
        let relativePath = url.path.replacingOccurrences(of: workingDirectory.path + "/", with: "")
        if relativePath == url.path || relativePath.isEmpty {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(relativePath)
    }

    private func enumerateRecursively(at url: URL, into items: inout [FileProviderItem]) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for childURL in contents {
            let identifier = itemIdentifier(for: childURL)
            items.append(FileProviderItem(url: childURL, identifier: identifier, workingDirectory: workingDirectory))

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: childURL.path, isDirectory: &isDir), isDir.boolValue {
                enumerateRecursively(at: childURL, into: &items)
            }
        }
    }
}
