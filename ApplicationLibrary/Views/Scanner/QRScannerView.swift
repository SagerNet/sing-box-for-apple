#if !os(tvOS)

    import AVFoundation
    import Library
    import SwiftUI

    @MainActor
    public struct QRScannerView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var alert: AlertState?
        @StateObject private var controller = QRScannerController()

        private let onScan: (QRScanResult) -> Void

        public init(onScan: @escaping (QRScanResult) -> Void) {
            self.onScan = onScan
        }

        public var body: some View {
            #if os(iOS)
                iOSBody
            #elseif os(macOS)
                macOSBody
            #endif
        }

        #if os(iOS)
            private var iOSBody: some View {
                NavigationStackCompat {
                    QRScannerControllerView(controller: controller)
                        .ignoresSafeArea()
                        .navigationTitle("Scan QR Code")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Menu {
                                    if controller.availableCameras.count > 1 {
                                        Menu("Camera") {
                                            ForEach(controller.availableCameras, id: \.uniqueID) { camera in
                                                Button {
                                                    controller.selectCamera(camera)
                                                } label: {
                                                    if camera.uniqueID == controller.selectedCamera?.uniqueID {
                                                        Label(camera.localizedName, systemImage: "checkmark")
                                                    } else {
                                                        Text(camera.localizedName)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                }
                .alert($alert)
                .onAppear {
                    controller.onScan = handleScanResult
                }
            }
        #endif

        #if os(macOS)
            private var macOSBody: some View {
                VStack(spacing: 0) {
                    QRScannerControllerView(controller: controller)
                        .frame(minWidth: 400, minHeight: 300)

                    Divider()

                    HStack {
                        if controller.availableCameras.count > 1 {
                            Picker("Camera", selection: Binding(
                                get: { controller.selectedCamera },
                                set: { camera in
                                    if let camera {
                                        controller.selectCamera(camera)
                                    }
                                }
                            )) {
                                ForEach(controller.availableCameras, id: \.uniqueID) { camera in
                                    Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                                }
                            }
                            .frame(maxWidth: 250)
                        }
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                }
                .alert($alert)
                .onAppear {
                    controller.onScan = handleScanResult
                }
            }
        #endif

        private func handleScanResult(_ result: Result<QRScanResult, QRScanError>) {
            switch result {
            case let .success(scanResult):
                dismiss()
                onScan(scanResult)
            case let .failure(error):
                switch error {
                case .permissionDenied:
                    alert = AlertState(
                        title: String(localized: "Camera Access Denied"),
                        message: String(localized: "Please enable camera access in Settings to scan QR codes.")
                    )
                default:
                    alert = AlertState(
                        title: String(localized: "Scanner Error"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

#endif
