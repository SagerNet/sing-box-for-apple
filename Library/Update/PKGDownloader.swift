#if os(macOS)

    import Foundation

    public enum PKGDownloader {
        public static func download(
            from url: String,
            expectedSize: Int64,
            progress: @escaping (Double) -> Void
        ) async throws -> URL {
            let updatesDir = FilePath.cacheDirectory.appendingPathComponent("updates", isDirectory: true)
            try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)

            let filename = URL(string: url)!.lastPathComponent
            let destination = updatesDir.appendingPathComponent(filename)

            if let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let fileSize = attrs[.size] as? Int64,
               expectedSize > 0, fileSize == expectedSize
            {
                progress(1.0)
                return destination
            }

            // Clean old PKG files
            if let contents = try? FileManager.default.contentsOfDirectory(at: updatesDir, includingPropertiesForKeys: nil) {
                for file in contents where file.pathExtension == "pkg" && file.lastPathComponent != filename {
                    try? FileManager.default.removeItem(at: file)
                }
            }

            try? FileManager.default.removeItem(at: destination)
            var lastReported = 0.0
            try await HTTPClient.writeToAsync(url, path: destination.path) { bytesWritten, totalBytes in
                guard totalBytes > 0 else { return }
                let current = Double(bytesWritten) / Double(totalBytes)
                guard current - lastReported >= 0.01 || current >= 1.0 else { return }
                lastReported = current
                progress(current)
            }
            return destination
        }
    }

#endif
