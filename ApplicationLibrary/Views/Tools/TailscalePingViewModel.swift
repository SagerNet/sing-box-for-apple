import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public final class TailscalePingViewModel: BaseViewModel {
    @Published public var isRunning = false
    @Published public var latencyMs: Double = 0
    @Published public var isDirect: Bool = false
    @Published public var derpRegionCode: String = ""
    @Published public var endpoint: String = ""
    @Published public var hasResult = false
    @Published public var latencyHistory: [CGFloat] = []

    private let maxHistorySize = 30
    private var commandClient: LibboxCommandClient?
    private var runningTask: Task<Void, Never>?

    public func start(endpointTag: String, peerIP: String) {
        latencyHistory = []
        hasResult = false
        isRunning = true

        let client = LibboxNewStandaloneCommandClient()!
        commandClient = client
        let handler = PingHandler(self)

        runningTask = Task { [weak self] in
            await Task.detached {
                try? client.startTailscalePing(endpointTag, peerIP: peerIP, handler: handler)
            }.value
            self?.runningTask = nil
        }
    }

    public func stop() {
        runningTask?.cancel()
        runningTask = nil
        try? commandClient?.disconnect()
        commandClient = nil
        isRunning = false
    }

    fileprivate func appendLatency(_ ms: Double) {
        latencyHistory.append(CGFloat(ms))
        if latencyHistory.count > maxHistorySize {
            latencyHistory.removeFirst()
        }
    }

    private final class PingHandler: NSObject, LibboxTailscalePingHandlerProtocol, @unchecked Sendable {
        private weak var viewModel: TailscalePingViewModel?

        init(_ viewModel: TailscalePingViewModel?) {
            self.viewModel = viewModel
        }

        func onPingResult(_ result: LibboxTailscalePingResult?) {
            guard let result else { return }
            let latencyMs = result.latencyMs
            let isDirect = result.isDirect
            let derpRegionCode = result.derpRegionCode
            let endpoint = result.endpoint
            let error = result.error
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                if !error.isEmpty {
                    return
                }
                viewModel.latencyMs = latencyMs
                viewModel.isDirect = isDirect
                viewModel.derpRegionCode = derpRegionCode
                viewModel.endpoint = endpoint
                viewModel.hasResult = true
                viewModel.appendLatency(latencyMs)
            }
        }

        func onError(_: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.isRunning = false
                viewModel.commandClient = nil
                viewModel.runningTask = nil
            }
        }
    }
}
