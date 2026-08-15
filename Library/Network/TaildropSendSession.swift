import Foundation
import Libbox

public struct TaildropSendFile: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let name: String
    public let size: Int64
    public var sentBytes: Int64 = 0
    public var completed = false

    let handle: FileHandle

    public init(_ url: URL, name: String) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory == true {
            throw NSError(domain: "Taildrop", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Taildrop cannot send the folder \(url.lastPathComponent)",
            ])
        }
        guard let fileSize = values.fileSize else {
            throw NSError(domain: "Taildrop", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a regular file",
            ])
        }
        var fileName = (name as NSString).lastPathComponent
        if fileName.isEmpty {
            fileName = url.lastPathComponent
        }
        self.name = fileName
        size = Int64(fileSize)
        handle = try FileHandle(forReadingFrom: url)
    }

    public func close() {
        try? handle.close()
    }
}

public final class TaildropSendSession: @unchecked Sendable {
    private let session: LibboxTaildropSendSession
    private let files: [TaildropSendFile]
    private let handler: SendHandler

    private init(_ session: LibboxTaildropSendSession, _ files: [TaildropSendFile], _ handler: SendHandler) {
        self.session = session
        self.files = files
        self.handler = handler
    }

    public static func start(
        endpointTag: String,
        peerStableID: String,
        files: [TaildropSendFile],
        onProgress: @escaping @Sendable (Int32, Int64) -> Void,
        onFileCompleted: @escaping @Sendable (Int32, Int64) -> Void,
        onFinish: @escaping @Sendable (String?) -> Void
    ) throws -> TaildropSendSession {
        let options = LibboxNewTaildropSendOptions()!
        options.endpointTag = endpointTag
        options.peerStableID = peerStableID
        for file in files {
            options.addFile(file.name, size: file.size)
        }
        let handler = SendHandler(progress: onProgress, fileCompleted: onFileCompleted, finish: onFinish)
        let libboxSession = try CommandTarget.standaloneClient().sendTaildropFiles(options, handler: handler)
        let session = TaildropSendSession(libboxSession, files, handler)
        Task.detached {
            await BlockingIO.run {
                session.write()
            }
        }
        return session
    }

    public func close() {
        try? session.close()
    }

    private func write() {
        defer {
            for file in files {
                file.close()
            }
        }
        do {
            for file in files {
                while true {
                    let chunk = try file.handle.read(upToCount: Int(LibboxTaildropChunkSize))
                    guard let chunk, !chunk.isEmpty else {
                        break
                    }
                    try session.writeChunk(chunk)
                }
                try session.finishFile()
            }
        } catch {
            handler.onFinish(error.localizedDescription)
            close()
        }
    }

    private final class SendHandler: NSObject, LibboxTaildropSendHandlerProtocol, @unchecked Sendable {
        private let progress: @Sendable (Int32, Int64) -> Void
        private let fileCompleted: @Sendable (Int32, Int64) -> Void
        private let finish: @Sendable (String?) -> Void
        private let finishAccess = NSLock()
        private var finishReported = false

        init(
            progress: @escaping @Sendable (Int32, Int64) -> Void,
            fileCompleted: @escaping @Sendable (Int32, Int64) -> Void,
            finish: @escaping @Sendable (String?) -> Void
        ) {
            self.progress = progress
            self.fileCompleted = fileCompleted
            self.finish = finish
        }

        func onProgress(_ fileIndex: Int32, sentBytes: Int64) {
            progress(fileIndex, sentBytes)
        }

        func onFileCompleted(_ fileIndex: Int32, sentBytes: Int64) {
            fileCompleted(fileIndex, sentBytes)
        }

        func onFinish(_ errorMessage: String?) {
            finishAccess.lock()
            let alreadyReported = finishReported
            finishReported = true
            finishAccess.unlock()
            guard !alreadyReported else { return }
            finish(errorMessage)
        }
    }
}
