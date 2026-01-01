#if os(macOS)

    import AppKit
    import AVFoundation
    import SwiftUI
    import Vision

    @MainActor
    final class QRSScannerController: NSObject, ObservableObject {
        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var videoOutput: AVCaptureVideoDataOutput?

        @Published var decoder = LubyTransformDecoder()
        @Published var lastError: String?
        @Published var isComplete = false
        @Published var progress: Double = 0
        @Published var framesScanned = 0
        @Published var availableCameras: [AVCaptureDevice] = []
        @Published var selectedCamera: AVCaptureDevice?

        private var seenBlockHashes = Set<Data>()

        let previewView = NSView()
        var onComplete: ((Data) -> Void)?

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

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "QRSScannerQueue"))

            guard session.canAddOutput(videoOutput) else { return }
            session.addOutput(videoOutput)

            self.videoOutput = videoOutput
            captureSession = session

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

        private func processQRContent(_ content: String) {
            guard !isComplete else { return }

            guard let block = EncodedBlock.fromBase64(content) else {
                return
            }

            let hash = block.toBinary()
            guard !seenBlockHashes.contains(hash) else { return }
            seenBlockHashes.insert(hash)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                framesScanned += 1

                do {
                    let complete = try decoder.addBlock(block)
                    progress = decoder.progress

                    if complete {
                        isComplete = true
                        stopScanning()
                        NSSound.beep()

                        if let data = try? decoder.getDecoded() {
                            onComplete?(data)
                        }
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
    }

    extension QRSScannerController: AVCaptureVideoDataOutputSampleBufferDelegate {
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
                        self?.processQRContent(payload)
                    }
                }
            }
            request.symbologies = [.qr]

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform([request])
        }
    }

    struct QRSScannerControllerView: NSViewControllerRepresentable {
        let controller: QRSScannerController

        func makeNSViewController(context: Context) -> NSViewController {
            let viewController = QRSScannerViewController(controller: controller)
            return viewController
        }

        func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    }

    private class QRSScannerViewController: NSViewController {
        let controller: QRSScannerController

        init(controller: QRSScannerController) {
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
