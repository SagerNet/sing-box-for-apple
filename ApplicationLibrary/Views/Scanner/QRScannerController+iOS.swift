#if os(iOS)

    import AVFoundation
    import SwiftUI
    import UIKit

    @MainActor
    final class QRScannerController: NSObject, ObservableObject {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var metadataOutput: AVCaptureMetadataOutput?
        private var didFinishScanning = false

        @Published var availableCameras: [AVCaptureDevice] = []
        @Published var selectedCamera: AVCaptureDevice?

        @Published var qrsMode = false
        @Published var decoder: LubyTransformDecoder?
        @Published var progress: Double = 0
        @Published var framesScanned = 0
        private var seenBlockIds = Set<String>()
        private let decodingQueue = DispatchQueue(label: "QRSDecoding", qos: .userInitiated)

        let previewView = UIView()
        var onScan: ((Result<QRScanResult, QRScanError>) -> Void)?

        override init() {
            super.init()
            previewView.backgroundColor = .black
            refreshCameraList()
        }

        func refreshCameraList() {
            var deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
            ]
            if #available(iOS 17.0, *) {
                deviceTypes.append(.external)
            }
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
            availableCameras = discoverySession.devices
            if selectedCamera == nil {
                selectedCamera = availableCameras.first
            }
        }

        func selectCamera(_ camera: AVCaptureDevice) {
            guard camera.uniqueID != selectedCamera?.uniqueID else { return }
            selectedCamera = camera
            didFinishScanning = false

            if captureSession != nil {
                stopScanning()
                captureSession = nil
                previewLayer?.removeFromSuperlayer()
                previewLayer = nil
                startScanning()
            }
        }

        func startScanning() {
            guard captureSession == nil else {
                if captureSession?.isRunning == false {
                    DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                        self?.captureSession?.startRunning()
                    }
                }
                return
            }

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                setupCaptureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted {
                            self?.setupCaptureSession()
                        } else {
                            self?.onScan?(.failure(.permissionDenied))
                        }
                    }
                }
            case .denied, .restricted:
                onScan?(.failure(.permissionDenied))
            @unknown default:
                onScan?(.failure(.cameraUnavailable))
            }
        }

        func stopScanning() {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }

        func reset() {
            didFinishScanning = false
            qrsMode = false
            decoder = nil
            progress = 0
            framesScanned = 0
            seenBlockIds.removeAll()
        }

        private func setupCaptureSession() {
            let session = AVCaptureSession()

            guard let videoCaptureDevice = selectedCamera ?? AVCaptureDevice.default(for: .video) else {
                onScan?(.failure(.cameraUnavailable))
                return
            }

            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                onScan?(.failure(.scanFailed(error)))
                return
            }

            guard session.canAddInput(videoInput) else {
                onScan?(.failure(.cameraUnavailable))
                return
            }
            session.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else {
                onScan?(.failure(.cameraUnavailable))
                return
            }
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]

            self.metadataOutput = metadataOutput
            captureSession = session

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = previewView.bounds
            previewView.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }

        func updatePreviewFrame(_ frame: CGRect) {
            previewLayer?.frame = frame
        }
    }

    extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
        nonisolated func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            Task { @MainActor in
                guard !didFinishScanning else { return }

                for metadataObject in metadataObjects {
                    guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                          let stringValue = readableObject.stringValue
                    else { continue }

                    processScannedContent(stringValue, type: readableObject.type)
                }
            }
        }

        private func processScannedContent(_ content: String, type: AVMetadataObject.ObjectType) {
            if let block = EncodedBlock.fromQRSString(content) {
                processQRSBlock(block)
            } else if !qrsMode {
                didFinishScanning = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                onScan?(.success(.qrCode(string: content, type: type)))
            }
        }

        private func processQRSBlock(_ block: EncodedBlock) {
            if let currentChecksum = decoder?.meta?.checksum,
               block.checksum != currentChecksum
            {
                decoder = LubyTransformDecoder()
                seenBlockIds.removeAll()
                progress = 0
                framesScanned = 0
            }

            if !qrsMode {
                qrsMode = true
                decoder = LubyTransformDecoder()
            }

            let blockId = "\(block.checksum):\(block.indices.sorted().map(String.init).joined(separator: ","))"
            guard !seenBlockIds.contains(blockId) else { return }
            seenBlockIds.insert(blockId)

            framesScanned += 1

            guard let decoder else { return }
            decodingQueue.async { [weak self] in
                do {
                    let complete = try decoder.addBlock(block)
                    let currentProgress = decoder.progress

                    DispatchQueue.main.async {
                        guard let self, !self.didFinishScanning else { return }
                        self.progress = currentProgress

                        if complete {
                            self.didFinishScanning = true
                            self.stopScanning()
                            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

                            if let data = try? decoder.getDecoded() {
                                self.onScan?(.success(.qrsData(data)))
                            } else {
                                self.onScan?(.failure(.qrsDecodeFailed))
                            }
                        }
                    }
                } catch {
                    // Checksum mismatch is handled above, ignore other errors
                }
            }
        }
    }

    struct QRScannerControllerView: UIViewControllerRepresentable {
        let controller: QRScannerController

        func makeUIViewController(context _: Context) -> UIViewController {
            QRScannerViewController(controller: controller)
        }

        func updateUIViewController(_: UIViewController, context _: Context) {}
    }

    private class QRScannerViewController: UIViewController {
        let controller: QRScannerController

        init(controller: QRScannerController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            view.addSubview(controller.previewView)
            controller.previewView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.previewView.topAnchor.constraint(equalTo: view.topAnchor),
                controller.previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                controller.previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                controller.previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            controller.updatePreviewFrame(view.bounds)
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            controller.startScanning()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            controller.stopScanning()
        }
    }

#endif
