#if os(iOS)

    import Foundation
    import Library
    import Network
    import os
    import UIKit

    private let logger = Logger(category: "ReportTransferServer")

    public extension Notification.Name {
        static let reportReceived = Notification.Name("reportReceived")
    }

    public class ReportTransferServer {
        private var listener: NWListener

        @available(iOS 16.0, *)
        public init() throws {
            listener = try NWListener(using: .applicationService)
            listener.service = NWListener.Service(applicationService: ReportTransferService.applicationServiceName)
            listener.newConnectionHandler = { connection in
                connection.stateUpdateHandler = { state in
                    if state == .ready {
                        Task.detached {
                            try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 100)
                            await ReportTransferConnection(connection).process()
                        }
                    }
                }
                connection.start(queue: .global())
            }
        }

        public func start() {
            listener.start(queue: .global())
        }

        public func cancel() {
            listener.cancel()
        }

        class ReportTransferConnection {
            private let connection: NWSocket
            private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

            init(_ connection: NWConnection) {
                self.connection = NWSocket(connection)
            }

            func process() async {
                beginBackgroundTask()
                defer { endBackgroundTask() }

                do {
                    let message = try await connection.read()
                    guard let type = ReportTransferMessage.decodeType(message) else {
                        throw ReportTransferError("Invalid report transfer message")
                    }
                    switch type {
                    case .report:
                        let manifest = try ReportTransferMessage.decodeReport(message)
                        try await importReport(manifest)
                        logger.info("report transfer server: received report")
                        await MainActor.run {
                            NotificationCenter.default.post(name: .reportReceived, object: manifest.reportType)
                        }
                        try await connection.write(ReportTransferMessage.encodeAck())
                    case .error:
                        let errorMsg = ReportTransferMessage.decodeError(message)
                        logger.warning("report transfer server: client error: \(errorMsg)")
                    case .complete, .ack:
                        throw ReportTransferError("Unexpected report transfer message")
                    }
                } catch {
                    logger.warning("report transfer server: \(error.localizedDescription)")
                    await writeError(error.localizedDescription)
                }
            }

            private func importReport(_ manifest: ReportTransferManifest) async throws {
                guard !manifest.files.isEmpty else {
                    throw ReportTransferError("Report is empty")
                }

                let expectedBytes = manifest.files.reduce(0) { $0 + $1.size }
                guard expectedBytes == manifest.totalBytes else {
                    throw ReportTransferError("Invalid report manifest")
                }

                let reportsDir = FilePath.workingDirectory.appendingPathComponent(manifest.reportType.directoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

                let date = Date(timeIntervalSince1970: manifest.timestamp)
                let artifactURL = ReportArchive.nextAvailableArtifactURL(in: reportsDir, for: date)
                let stagingURL = nextAvailableStagingArtifactURL(in: reportsDir, for: artifactURL.lastPathComponent)
                try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)

                do {
                    var receivedBytes: UInt64 = 0
                    for file in manifest.files {
                        let fileURL = stagingURL.appendingPathComponent(file.name)
                        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                        do {
                            let handle = try FileHandle(forWritingTo: fileURL)
                            defer { try? handle.close() }

                            var remaining = file.size
                            while remaining > 0 {
                                let chunkSize = Int(min(UInt64(ReportTransferService.fileChunkSize), remaining))
                                let data = try await connection.readRaw(count: chunkSize)
                                try handle.write(contentsOf: data)
                                remaining -= UInt64(data.count)
                                receivedBytes += UInt64(data.count)
                            }
                        }
                    }

                    guard receivedBytes == manifest.totalBytes else {
                        throw ReportTransferError("Report transfer was incomplete")
                    }

                    let completion = try await connection.read()
                    guard let completionType = ReportTransferMessage.decodeType(completion) else {
                        throw ReportTransferError("Invalid report transfer message")
                    }
                    switch completionType {
                    case .complete:
                        break
                    case .error:
                        throw ReportTransferError(ReportTransferMessage.decodeError(completion))
                    case .report, .ack:
                        throw ReportTransferError("Unexpected report transfer message")
                    }

                    let metadataURL = stagingURL.appendingPathComponent(ReportArchive.metadataFileName)
                    if FileManager.default.fileExists(atPath: metadataURL.path) {
                        let metadataData = try Data(contentsOf: metadataURL)
                        try writeMetadataWithDeviceOrigin(metadataData, to: metadataURL)
                    }

                    try FileManager.default.moveItem(at: stagingURL, to: artifactURL)
                } catch {
                    try? FileManager.default.removeItem(at: stagingURL)
                    throw error
                }
            }

            private func nextAvailableStagingArtifactURL(in directory: URL, for artifactName: String) -> URL {
                var index = 0
                while true {
                    let suffix = index == 0 ? "" : "-\(index)"
                    let candidate = directory.appendingPathComponent(".\(artifactName).partial\(suffix)", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                    index += 1
                }
            }

            private func writeMetadataWithDeviceOrigin(_ data: Data, to url: URL) throws {
                guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    try data.write(to: url, options: .atomic)
                    return
                }
                json["deviceOrigin"] = ReportArchive.tvOSDeviceOrigin
                let patched = try JSONSerialization.data(withJSONObject: json)
                try patched.write(to: url, options: .atomic)
            }

            private func writeError(_ message: String) async {
                try? await connection.write(ReportTransferMessage.encodeError(message))
            }

            private func beginBackgroundTask() {
                backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
                    logger.warning("report transfer server: background task expiring")
                    self?.connection.cancel()
                    self?.endBackgroundTask()
                }
            }

            private func endBackgroundTask() {
                guard backgroundTaskID != .invalid else { return }
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
    }

#endif
