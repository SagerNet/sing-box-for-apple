import Foundation

public extension Profile {
    func read() throws -> String {
        #if DEBUG
            precondition(!Thread.isMainThread, "Profile.read() must not be called on the main thread")
        #endif
        switch type {
        case .local, .remote:
            return try String(contentsOfFile: path)
        case .icloud:
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            return try String(contentsOf: saveURL)
        }
    }

    func write(_ content: String) throws {
        #if DEBUG
            precondition(!Thread.isMainThread, "Profile.write(...) must not be called on the main thread")
        #endif
        switch type {
        case .local, .remote:
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        case .icloud:
            let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
            try content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }

    func readAsync() async throws -> String {
        let type = type
        let path = path
        return try await BlockingIO.run {
            switch type {
            case .local, .remote:
                return try String(contentsOfFile: path)
            case .icloud:
                let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
                return try String(contentsOf: saveURL)
            }
        }
    }

    func writeAsync(_ content: String) async throws {
        let type = type
        let path = path
        let content = content
        try await BlockingIO.run {
            switch type {
            case .local, .remote:
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            case .icloud:
                let saveURL = FilePath.iCloudDirectory.appendingPathComponent(path)
                try content.write(to: saveURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
