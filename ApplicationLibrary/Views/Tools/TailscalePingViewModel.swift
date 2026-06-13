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
    @Published public var pingError: String = ""
    @Published public var latencyHistory: [CGFloat] = []

    private let maxHistorySize = 30
    private var pingSession: LibboxTailscalePingSession?

    public func start(endpointTag: String, peerIP: String) {
        latencyHistory = []
        hasResult = false
        pingError = ""
        isRunning = true

        let handler = PingHandler(self)

        Task { [weak self] in
            do {
                let session = try await Task.detached {
                    try CommandTarget.standaloneClient().startTailscalePing(endpointTag, peerIP: peerIP, handler: handler)
                }.value
                self?.pingSession = session
            } catch {
                guard let self else { return }
                self.isRunning = false
            }
        }
    }

    public func stop() {
        try? pingSession?.close()
        pingSession = nil
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
                    viewModel.pingError = error
                    return
                }
                viewModel.latencyMs = latencyMs
                viewModel.isDirect = isDirect
                viewModel.derpRegionCode = derpRegionCode
                viewModel.endpoint = endpoint
                viewModel.pingError = ""
                viewModel.hasResult = true
                viewModel.appendLatency(latencyMs)
            }
        }

        func onError(_: String?) {
            DispatchQueue.main.async { [self] in
                guard let viewModel, viewModel.isRunning else { return }
                viewModel.isRunning = false
                viewModel.pingSession = nil
            }
        }
    }
}
