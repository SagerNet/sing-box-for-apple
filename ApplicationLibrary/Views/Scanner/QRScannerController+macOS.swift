#if os(macOS)

    import AppKit
    import AVFoundation
    import SwiftUI
    import Vision

    @MainActor
    final class QRScannerController: NSObject, ObservableObject {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var videoOutput: AVCaptureVideoDataOutput?
        private var didFinishScanning = false

        @Published var availableCameras: [AVCaptureDevice] = []
        @Published var selectedCamera: AVCaptureDevice?

        let previewView = NSView()
        var onScan: ((Result<QRScanResult, QRScanError>) -> Void)?

        override init() {
            super.init()
            previewView.wantsLayer = true
            previewView.layer?.backgroundColor = NSColor.black.cgColor
            refreshCameraList()
        }

        func refreshCameraList() {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
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

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "QRScannerQueue"))

            guard session.canAddOutput(videoOutput) else {
                onScan?(.failure(.cameraUnavailable))
                return
            }
            session.addOutput(videoOutput)

            self.videoOutput = videoOutput
            self.captureSession = session

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = previewView.bounds
            previewView.layer?.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }

        func updatePreviewFrame(_ frame: CGRect) {
            previewLayer?.frame = frame
        }

        private func processQRCode(_ payloadString: String) {
            guard !didFinishScanning else { return }
            didFinishScanning = true

            DispatchQueue.main.async { [weak self] in
                NSSound.beep()
                let result = QRScanResult(string: payloadString, type: .qr)
                self?.onScan?(.success(result))
            }
        }
    }

    extension QRScannerController: AVCaptureVideoDataOutputSampleBufferDelegate {
        nonisolated func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let request = VNDetectBarcodesRequest { [weak self] request, _ in
                guard let results = request.results as? [VNBarcodeObservation] else { return }

                for result in results {
                    if result.symbology == .qr, let payload = result.payloadStringValue {
                        self?.processQRCode(payload)
                        return
                    }
                }
            }
            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }

    struct QRScannerControllerView: NSViewControllerRepresentable {
        let controller: QRScannerController

        func makeNSViewController(context: Context) -> NSViewController {
            let viewController = QRScannerViewController(controller: controller)
            return viewController
        }

        func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    }

    private class QRScannerViewController: NSViewController {
        let controller: QRScannerController

        init(controller: QRScannerController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.addSubview(controller.previewView)
            controller.previewView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.previewView.topAnchor.constraint(equalTo: view.topAnchor),
                controller.previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                controller.previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                controller.previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            controller.updatePreviewFrame(view.bounds)
        }

        override func viewWillAppear() {
            super.viewWillAppear()
            controller.startScanning()
        }

        override func viewWillDisappear() {
            super.viewWillDisappear()
            controller.stopScanning()
        }
    }

#endif
