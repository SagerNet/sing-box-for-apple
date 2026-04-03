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

                var receivedCount = 0
                var lastReportType: ReportType?
                do {
                    while true {
                        let message = try await connection.read()
                        guard let type = ReportTransferMessage.decodeType(message) else {
                            continue
                        }
                        switch type {
                        case .report:
                            let payload = try ReportTransferMessage.decodeReport(message)
                            try importReport(payload)
                            lastReportType = payload.reportType
                            receivedCount += 1
                        case .complete:
                            logger.info("report transfer server: received \(receivedCount) report(s)")
                            if receivedCount > 0 {
                                let reportType = lastReportType
                                await MainActor.run {
                                    NotificationCenter.default.post(name: .reportReceived, object: reportType)
                                }
                            }
                            try await connection.write(ReportTransferMessage.encodeAck())
                            return
                        case .error:
                            let errorMsg = ReportTransferMessage.decodeError(message)
                            logger.warning("report transfer server: client error: \(errorMsg)")
                            return
                        case .ack:
                            return
                        }
                    }
                } catch {
                    logger.warning("report transfer server: \(error.localizedDescription)")
                    await writeError(error.localizedDescription)
                }
            }

            private func importReport(_ payload: ReportTransferPayload) throws {
                let reportsDir = FilePath.workingDirectory.appendingPathComponent(payload.reportType.directoryName, isDirectory: true)
                try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

                let date = Date(timeIntervalSince1970: payload.timestamp)
                let artifactURL = ReportArchive.nextAvailableArtifactURL(in: reportsDir, for: date)
                try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)

                for file in payload.files {
                    let fileURL = artifactURL.appendingPathComponent(file.name)
                    if file.name == ReportArchive.metadataFileName {
                        try writeMetadataWithDeviceOrigin(file.data, to: fileURL)
                    } else {
                        try file.data.write(to: fileURL, options: .atomic)
                    }
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
