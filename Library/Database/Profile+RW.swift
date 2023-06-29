import Foundation

public extension Profile {
    func read() throws -> String {
        switch type {
        case .local, .remote:
            return try String(contentsOfFile: path)
        case .icloud:
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            _ = saveURL.startAccessingSecurityScopedResource()
            defer {
                saveURL.stopAccessingSecurityScopedResource()
            }
            return try String(contentsOf: saveURL)
        }
    }

    func write(_ content: String) throws {
        switch type {
        case .local, .remote:
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        case .icloud:
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            _ = saveURL.startAccessingSecurityScopedResource()
            defer {
                saveURL.stopAccessingSecurityScopedResource()
            }
            try content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
}
