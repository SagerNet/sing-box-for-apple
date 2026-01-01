#if os(iOS)

    import AVFoundation
    import SwiftUI
    import UIKit

    @MainActor
    final class QRSScannerController: NSObject, ObservableObject {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var metadataOutput: AVCaptureMetadataOutput?

        @Published var decoder = LubyTransformDecoder()
        @Published var lastError: String?
        @Published var isComplete = false
        @Published var progress: Double = 0
        @Published var framesScanned = 0
        @Published var availableCameras: [AVCaptureDevice] = []
        @Published var selectedCamera: AVCaptureDevice?

        private var seenBlockHashes = Set<Data>()

        let previewView = UIView()
        var onComplete: ((Data) -> Void)?

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

            if captureSession != nil {
                stopScanning()
                captureSession = nil
                previewLayer?.removeFromSuperlayer()
                previewLayer = nil
                startScanning()
            }
        }

        func reset() {
            decoder = LubyTransformDecoder()
            seenBlockHashes.removeAll()
            lastError = nil
            isComplete = false
            progress = 0
            framesScanned = 0
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
                        }
                    }
                }
            default:
                break
            }
        }

        func stopScanning() {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }

        private func setupCaptureSession() {
            let session = AVCaptureSession()

            guard let videoCaptureDevice = selectedCamera ?? AVCaptureDevice.default(for: .video) else {
                return
            }

            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                return
            }

            guard session.canAddInput(videoInput) else { return }
            session.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else { return }
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

        private func processQRContent(_ content: String) {
            guard !isComplete else { return }

            guard let block = EncodedBlock.fromBase64(content) else {
                return
            }

            let hash = block.toBinary()
            guard !seenBlockHashes.contains(hash) else { return }
            seenBlockHashes.insert(hash)

            framesScanned += 1

            do {
                let complete = try decoder.addBlock(block)
                progress = decoder.progress

                if complete {
                    isComplete = true
                    stopScanning()
                    AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

                    if let data = try? decoder.getDecoded() {
                        onComplete?(data)
                    }
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    extension QRSScannerController: AVCaptureMetadataOutputObjectsDelegate {
        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            Task { @MainActor in
                for metadataObject in metadataObjects {
                    guard let readable = metadataObject as? AVMetadataMachineReadableCodeObject,
                          let content = readable.stringValue
                    else { continue }
                    processQRContent(content)
                }
            }
        }
    }

    struct QRSScannerControllerView: UIViewControllerRepresentable {
        let controller: QRSScannerController

        func makeUIViewController(context: Context) -> UIViewController {
            let viewController = QRSScannerViewController(controller: controller)
            return viewController
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    }

    private class QRSScannerViewController: UIViewController {
        let controller: QRSScannerController

        init(controller: QRSScannerController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
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
