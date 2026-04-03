#if os(tvOS)

    import DeviceDiscoveryUI
    import Library
    import Network
    import SwiftUI

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
            let fm = FileManager.default
            guard let fileURLs = try? fm.contentsOfDirectory(
                at: reportURL,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else {
                throw ReportTransferError("Report is empty")
            }

            var files: [ReportTransferFile] = []
            for fileURL in fileURLs {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                files.append(ReportTransferFile(name: fileURL.lastPathComponent, data: data))
            }

            guard !files.isEmpty else {
                throw ReportTransferError("Report is empty")
            }

            let payload = ReportTransferPayload(
                reportType: reportType,
                timestamp: reportDate.timeIntervalSince1970,
                files: files
            )
            try await socket.write(ReportTransferMessage.encodeReport(payload))
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
    }

#endif
