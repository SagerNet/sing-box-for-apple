#if os(tvOS)

    import DeviceDiscoveryUI
    import Library
    import Network
    import SwiftUI

    private struct StreamedReportFile {
        let name: String
        let fileURL: URL
        let size: UInt64
    }

    @MainActor
    public struct ExportReportView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var viewModel = ExportReportViewModel()

        let reportType: ReportType
        let reportURL: URL
        let reportDate: Date

        public init(reportType: ReportType, reportURL: URL, reportDate: Date) {
            self.reportType = reportType
            self.reportURL = reportURL
            self.reportDate = reportDate
        }

        public var body: some View {
            VStack(alignment: .center) {
                if !viewModel.selected {
                    Form {
                        Section {
                            EmptyView()
                        } footer: {
                            Text("To export this report to your iPhone or iPad, make sure sing-box is the **same version** on both devices and **VPN is disabled**.")
                        }

                        DevicePicker(
                            .applicationService(name: ReportTransferService.applicationServiceName)
                        ) { endpoint in
                            viewModel.selected = true
                            Task {
                                await viewModel.handleEndpoint(endpoint, reportType: reportType, reportURL: reportURL, reportDate: reportDate)
                            }
                        } label: {
                            Text("Select Device")
                        } fallback: {
                            EmptyView()
                        } parameters: {
                            .applicationService
                        }
                    }
                } else if viewModel.exportComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Export Complete")
                            .font(.headline)
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Sending...")
                    }
                }
            }
            .focusSection()
            .alert($viewModel.alert)
            .navigationTitle("Export Report")
            .onChange(of: viewModel.exportComplete) { newValue in
                if newValue {
                    Task {
                        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 2)
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private final class ExportReportViewModel: BaseViewModel {
        @Published var selected = false
        @Published var exportComplete = false

        private var connection: NWConnection?
        private var socket: NWSocket?

        func reset() {
            cancelConnection()
            selected = false
        }

        private func cancelConnection() {
            if let connection {
                connection.stateUpdateHandler = nil
                connection.cancel()
                self.connection = nil
            }
            if let socket {
                socket.cancel()
                self.socket = nil
            }
        }

        func handleEndpoint(_ endpoint: NWEndpoint, reportType: ReportType, reportURL: URL, reportDate: Date) async {
            let connection = NWConnection(to: endpoint, using: NWParameters.applicationService)
            self.connection = connection
            let socket = NWSocket(connection)
            self.socket = socket

            connection.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    DispatchQueue.main.async { [self] in
                        reset()
                        alert = AlertState(action: "connect to device", error: error)
                    }
                default: break
                }
            }
            connection.start(queue: .global())

            do {
                try await sendReport(reportType: reportType, reportURL: reportURL, reportDate: reportDate, via: socket)
                cancelConnection()
                exportComplete = true
            } catch {
                alert = AlertState(action: "export report", error: error)
                reset()
            }
        }

        private nonisolated func sendReport(reportType: ReportType, reportURL: URL, reportDate: Date, via socket: NWSocket) async throws {
            let files = try collectFiles(in: reportURL)
            guard !files.isEmpty else {
                throw ReportTransferError("Report is empty")
            }

            let totalBytes = files.reduce(0) { $0 + $1.size }
            let manifest = ReportTransferManifest(
                reportType: reportType,
                timestamp: reportDate.timeIntervalSince1970,
                totalBytes: totalBytes,
                files: files.map { ReportTransferManifestFile(name: $0.name, size: $0.size) }
            )
            try await socket.write(ReportTransferMessage.encodeReport(manifest))

            for file in files {
                try await streamFile(file, via: socket)
            }
            try await socket.write(ReportTransferMessage.encodeComplete())

            let response = try await socket.read()
            guard let responseType = ReportTransferMessage.decodeType(response) else {
                throw NWSocketError.connectionClosed
            }
            switch responseType {
            case .ack:
                break
            case .error:
                throw ReportTransferError(ReportTransferMessage.decodeError(response))
            default:
                throw NWSocketError.connectionClosed
            }
        }

        private nonisolated func collectFiles(in reportURL: URL) throws -> [StreamedReportFile] {
            let fm = FileManager.default
            let fileURLs = try fm.contentsOfDirectory(
                at: reportURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            var files: [StreamedReportFile] = []
            for fileURL in fileURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else {
                    continue
                }
                let size = UInt64(values.fileSize ?? 0)
                files.append(StreamedReportFile(name: fileURL.lastPathComponent, fileURL: fileURL, size: size))
            }
            return files
        }

        private nonisolated func streamFile(_ file: StreamedReportFile, via socket: NWSocket) async throws {
            let handle = try FileHandle(forReadingFrom: file.fileURL)
            defer { try? handle.close() }

            var remaining = file.size
            while remaining > 0 {
                let chunkSize = Int(min(UInt64(ReportTransferService.fileChunkSize), remaining))
                guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else {
                    throw ReportTransferError("Failed to read report file")
                }
                try await socket.writeRaw(data)
                remaining -= UInt64(data.count)
            }
        }
    }

#endif
