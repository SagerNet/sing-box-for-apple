import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class STUNTestViewModel: BaseViewModel, OutboundSelectable {
    @Published public var phase: Int32 = -1
    @Published public var externalAddr: String = ""
    @Published public var latencyMs: Int32 = 0
    @Published public var natMapping: Int32 = 0
    @Published public var natFiltering: Int32 = 0
    @Published public var natTypeSupported: Bool = false
    @Published public var isRunning = false
    @Published public var selectedOutbound: String = ""

    @Published public var server: String = LibboxSTUNDefaultServer {
        didSet {
            guard !isLoadingPreferences else { return }
            saveServerTask?.cancel()
            saveServerTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await SharedPreferences.stunServer.set(server)
            }
        }
    }

    private var isLoadingPreferences = false
    private var saveServerTask: Task<Void, Never>?
    private var standaloneTest: LibboxSTUNTest?
    private var runningTask: Task<Void, Never>?

    public func loadPreferences() async {
        isLoadingPreferences = true
        let saved = await SharedPreferences.stunServer.get()
        if !saved.isEmpty {
            server = saved
        }
        isLoadingPreferences = false
    }

    public func startTest(vpnConnected: Bool) {
        phase = -1
        externalAddr = ""
        latencyMs = 0
        natMapping = 0
        natFiltering = 0
        natTypeSupported = false
        isRunning = true

        let server = server
        let outboundTag = selectedOutbound

        if vpnConnected {
            let handler = TestHandler(self)
            runningTask = Task { [weak self] in
                do {
                    try await Task.detached {
                        try LibboxNewStandaloneCommandClient()!.startSTUNTest(server, outboundTag: outboundTag, handler: handler)
                    }.value
                } catch {
                    guard let self else { return }
                    self.isRunning = false
                    self.alert = AlertState(action: "STUN test", error: error)
                }
                self?.runningTask = nil
            }
        } else {
            let test = LibboxNewSTUNTest()!
            standaloneTest = test
            let handler = TestHandler(self)
            test.start(server, handler: handler)
        }
    }

    public func cancel() {
        runningTask?.cancel()
        runningTask = nil
        standaloneTest?.cancel()
        standaloneTest = nil
        isRunning = false
    }

    private final class TestHandler: NSObject, LibboxSTUNTestHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: STUNTestViewModel?

        init(_ viewModel: STUNTestViewModel?) {
            self.viewModel = viewModel
        }

        func onProgress(_ progress: LibboxSTUNTestProgress?) {
            guard let progress else { return }
            let phase = progress.phase
            let externalAddr = progress.externalAddr
            let latencyMs = progress.latencyMs
            let natMapping = progress.natMapping
            let natFiltering = progress.natFiltering
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.phase = phase
                if !externalAddr.isEmpty {
                    viewModel.externalAddr = externalAddr
                }
                if latencyMs > 0 {
                    viewModel.latencyMs = latencyMs
                }
                viewModel.natMapping = natMapping
                viewModel.natFiltering = natFiltering
            }
        }

        func onResult(_ result: LibboxSTUNTestResult?) {
            guard let result else { return }
            let externalAddr = result.externalAddr
            let latencyMs = result.latencyMs
            let natMapping = result.natMapping
            let natFiltering = result.natFiltering
            let natTypeSupported = result.natTypeSupported
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.phase = LibboxSTUNPhaseDone
                viewModel.externalAddr = externalAddr
                viewModel.latencyMs = latencyMs
                viewModel.natMapping = natMapping
                viewModel.natFiltering = natFiltering
                viewModel.natTypeSupported = natTypeSupported
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
