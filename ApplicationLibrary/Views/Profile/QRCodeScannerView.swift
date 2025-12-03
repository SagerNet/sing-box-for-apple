#if os(iOS)

    import AVFoundation
    import CodeScanner
    import Libbox
    import Library
    import SwiftUI

    @MainActor
    public struct QRCodeScannerView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var alert: AlertState?

        private let onScan: (LibboxImportRemoteProfile) -> Void

        public init(onScan: @escaping (LibboxImportRemoteProfile) -> Void) {
            self.onScan = onScan
        }

        public var body: some View {
            NavigationStackCompat {
                CodeScannerView(codeTypes: [.qr], showViewfinder: true) { response in
                    handleScan(response)
                }
                .ignoresSafeArea()
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .alert($alert)
        }

        private func handleScan(_ result: Result<ScanResult, ScanError>) {
            switch result {
            case let .success(scanResult):
                var error: NSError?
                let remoteProfile = LibboxParseRemoteProfileImportLink(scanResult.string, &error)
                if let error {
                    alert = AlertState(title: String(localized: "Invalid QR Code"), message: error.localizedDescription)
                    return
                }
                guard let remoteProfile else {
                    alert = AlertState(title: String(localized: "Invalid QR Code"), message: String(localized: "The QR code does not contain a valid profile import link."))
                    return
                }
                dismiss()
                onScan(remoteProfile)
            case let .failure(error):
                switch error {
                case .permissionDenied:
                    alert = AlertState(title: String(localized: "Camera Access Denied"), message: String(localized: "Please enable camera access in Settings to scan QR codes."))
                default:
                    alert = AlertState(title: String(localized: "Scanner Error"), message: String(describing: error))
                }
            }
        }
    }

#endif
