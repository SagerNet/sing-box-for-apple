import Foundation
import Libbox
import Library
import Network
import SwiftUI

public enum MaxRuntimeOption: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60

    public var id: Int {
        rawValue
    }

    public var label: String {
        "\(rawValue)s"
    }
}

@MainActor
public final class NetworkQualityViewModel: BaseViewModel, OutboundSelectable {
    @Published public var phase: Int32 = -1
    @Published public var idleLatencyMs: Int32 = 0
    @Published public var downloadCapacity: Int64 = 0
    @Published public var uploadCapacity: Int64 = 0
    @Published public var downloadRPM: Int32 = 0
    @Published public var uploadRPM: Int32 = 0
    @Published public var downloadCapacityAccuracy: Int32 = 0
    @Published public var uploadCapacityAccuracy: Int32 = 0
    @Published public var downloadRPMAccuracy: Int32 = 0
    @Published public var uploadRPMAccuracy: Int32 = 0
    @Published public var isRunning = false
    @Published public var selectedOutbound: String = ""

    @Published public var configURL: String = LibboxNetworkQualityDefaultConfigURL {
        didSet {
            guard !isLoadingPreferences else { return }
            saveConfigURLTask?.cancel()
            saveConfigURLTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await SharedPreferences.nqConfigURL.set(configURL)
            }
        }
    }

    @Published public var serial: Bool = false {
        didSet {
            guard !isLoadingPreferences else { return }
            Task {
                await SharedPreferences.nqSerial.set(serial)
            }
        }
    }

    @Published public var http3: Bool = false {
        didSet {
            guard !isLoadingPreferences else { return }
            Task {
                await SharedPreferences.nqHttp3.set(http3)
            }
        }
    }

    @Published public var maxRuntime: MaxRuntimeOption = .thirty {
        didSet {
            guard !isLoadingPreferences else { return }
            Task {
                await SharedPreferences.nqMaxRuntime.set(maxRuntime.rawValue)
            }
        }
    }

    private var isLoadingPreferences = false
    private var saveConfigURLTask: Task<Void, Never>?
    private var standaloneTest: LibboxNetworkQualityTest?
    private var runningTask: Task<Void, Never>?
    public func loadPreferences() async {
        isLoadingPreferences = true
        let savedURL = await SharedPreferences.nqConfigURL.get()
        if !savedURL.isEmpty {
            configURL = savedURL
        }
        serial = await SharedPreferences.nqSerial.get()
        http3 = await SharedPreferences.nqHttp3.get()
        let savedRuntime = await SharedPreferences.nqMaxRuntime.get()
        maxRuntime = MaxRuntimeOption(rawValue: savedRuntime) ?? .thirty
        isLoadingPreferences = false
    }

    private func checkMeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.isExpensive || path.usesInterfaceType(.cellular))
            }
            monitor.start(queue: DispatchQueue.global())
        }
    }

    public func requestStartTest(vpnConnected: Bool) {
        Task {
            let isMetered = await checkMeteredNetwork()
            if isMetered {
                alert = AlertState(
                    title: String(localized: "Metered Connection"),
                    message: String(localized: "You're on a metered connection. This test will use a significant amount of data."),
                    primaryButton: .cancel(),
                    secondaryButton: .destructive(String(localized: "Continue")) { [weak self] in
                        self?.startTest(vpnConnected: vpnConnected)
                    }
                )
            } else {
                startTest(vpnConnected: vpnConnected)
            }
        }
    }

    public func startTest(vpnConnected: Bool) {
        phase = -1
        idleLatencyMs = 0
        downloadCapacity = 0
        uploadCapacity = 0
        downloadRPM = 0
        uploadRPM = 0
        downloadCapacityAccuracy = 0
        uploadCapacityAccuracy = 0
        downloadRPMAccuracy = 0
        uploadRPMAccuracy = 0
        isRunning = true

        let configURL = configURL
        let outboundTag = selectedOutbound
        let serial = serial
        let http3 = http3
        let maxRuntimeSeconds = Int32(maxRuntime.rawValue)

        if vpnConnected {
            let handler = TestHandler(self)
            runningTask = Task { [weak self] in
                do {
                    try await Task.detached {
                        try LibboxNewStandaloneCommandClient()!.startNetworkQualityTest(configURL, outboundTag: outboundTag, serial: serial, maxRuntimeSeconds: maxRuntimeSeconds, http3: http3, handler: handler)
                    }.value
                } catch {
                    guard let self else { return }
                    self.isRunning = false
                    self.alert = AlertState(action: "network quality test", error: error)
                }
                self?.runningTask = nil
            }
        } else {
            let test = LibboxNewNetworkQualityTest()!
            standaloneTest = test
            let handler = TestHandler(self)
            test.start(configURL, serial: serial, maxRuntimeSeconds: maxRuntimeSeconds, http3: http3, handler: handler)
        }
    }

    fileprivate func applyMetrics(phase: Int32, idleLatencyMs: Int32, downloadCapacity: Int64, uploadCapacity: Int64, downloadRPM: Int32, uploadRPM: Int32, downloadCapacityAccuracy: Int32, uploadCapacityAccuracy: Int32, downloadRPMAccuracy: Int32, uploadRPMAccuracy: Int32) {
        self.phase = phase
        self.idleLatencyMs = idleLatencyMs
        self.downloadCapacity = downloadCapacity
        self.uploadCapacity = uploadCapacity
        self.downloadRPM = downloadRPM
        self.uploadRPM = uploadRPM
        self.downloadCapacityAccuracy = downloadCapacityAccuracy
        self.uploadCapacityAccuracy = uploadCapacityAccuracy
        self.downloadRPMAccuracy = downloadRPMAccuracy
        self.uploadRPMAccuracy = uploadRPMAccuracy
    }

    public func cancel() {
        runningTask?.cancel()
        runningTask = nil
        standaloneTest?.cancel()
        standaloneTest = nil
        isRunning = false
    }

    private final class TestHandler: NSObject, LibboxNetworkQualityTestHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: NetworkQualityViewModel?

        init(_ viewModel: NetworkQualityViewModel?) {
            self.viewModel = viewModel
        }

        func onProgress(_ progress: LibboxNetworkQualityProgress?) {
            guard let progress else { return }
            let phase = progress.phase
            let idleLatencyMs = progress.idleLatencyMs
            let downloadCapacity = progress.downloadCapacity
            let uploadCapacity = progress.uploadCapacity
            let downloadRPM = progress.downloadRPM
            let uploadRPM = progress.uploadRPM
            let downloadCapacityAccuracy = progress.downloadCapacityAccuracy
            let uploadCapacityAccuracy = progress.uploadCapacityAccuracy
            let downloadRPMAccuracy = progress.downloadRPMAccuracy
            let uploadRPMAccuracy = progress.uploadRPMAccuracy
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.applyMetrics(phase: phase, idleLatencyMs: idleLatencyMs, downloadCapacity: downloadCapacity, uploadCapacity: uploadCapacity, downloadRPM: downloadRPM, uploadRPM: uploadRPM, downloadCapacityAccuracy: downloadCapacityAccuracy, uploadCapacityAccuracy: uploadCapacityAccuracy, downloadRPMAccuracy: downloadRPMAccuracy, uploadRPMAccuracy: uploadRPMAccuracy)
            }
        }

        func onResult(_ result: LibboxNetworkQualityResult?) {
            guard let result else { return }
            let idleLatencyMs = result.idleLatencyMs
            let downloadCapacity = result.downloadCapacity
            let uploadCapacity = result.uploadCapacity
            let downloadRPM = result.downloadRPM
            let uploadRPM = result.uploadRPM
            let downloadCapacityAccuracy = result.downloadCapacityAccuracy
            let uploadCapacityAccuracy = result.uploadCapacityAccuracy
            let downloadRPMAccuracy = result.downloadRPMAccuracy
            let uploadRPMAccuracy = result.uploadRPMAccuracy
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.applyMetrics(phase: LibboxNetworkQualityPhaseDone, idleLatencyMs: idleLatencyMs, downloadCapacity: downloadCapacity, uploadCapacity: uploadCapacity, downloadRPM: downloadRPM, uploadRPM: uploadRPM, downloadCapacityAccuracy: downloadCapacityAccuracy, uploadCapacityAccuracy: uploadCapacityAccuracy, downloadRPMAccuracy: downloadRPMAccuracy, uploadRPMAccuracy: uploadRPMAccuracy)
                viewModel.isRunning = false
                viewModel.runningTask = nil
                viewModel.standaloneTest = nil
            }
        }

        func onError(_ message: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.isRunning = false
                viewModel.runningTask = nil
                viewModel.standaloneTest = nil
                if let message {
                    viewModel.alert = AlertState(errorMessage: message)
                }
            }
        }
    }
}
