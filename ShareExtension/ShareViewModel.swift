import Foundation
import Library
import UniformTypeIdentifiers

@MainActor
final class ShareViewModel: ObservableObject {
    @Published private(set) var files: [TaildropSendFile] = []
    @Published private(set) var endpoints: [TaildropTargetEndpoint] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false
    @Published private(set) var isFinished = false
    @Published private(set) var unavailableMessage: String?
    @Published var alert: AlertState?

    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onOpenApplication: ((URL) -> Void)?

    private var loaded = false
    private var session: TaildropSendSession?

    static func setupService() {
        do {
            try ServiceSetup.apply(crashReportSource: "ShareExtension")
        } catch {
            NSLog("setup service error: \(error.localizedDescription)")
        }
        do {
            try ApplicationLocale.apply()
        } catch {
            NSLog("failed to set locale: \(error)")
        }
    }

    func load(_ items: [NSExtensionItem]) {
        guard !loaded else { return }
        loaded = true
        let attachments = items.flatMap { $0.attachments ?? [] }
        Task {
            do {
                files = try await Self.open(attachments)
            } catch {
                isLoading = false
                presentError(error.localizedDescription)
                return
            }
            guard !files.isEmpty else {
                isLoading = false
                presentError("The shared item contains no file")
                return
            }
            let targets: TaildropTargetList
            do {
                targets = try await TaildropTargets.fetch()
            } catch {
                isLoading = false
                unavailableMessage = String(localized: "Service not started")
                return
            }
            endpoints = targets.endpoints
            if endpoints.isEmpty {
                if !targets.hasRunningEndpoint {
                    unavailableMessage = String(localized: "No Tailscale endpoint is running")
                } else if !targets.hasSharingEndpoint {
                    unavailableMessage = "File sharing is not enabled in the tailnet"
                } else {
                    unavailableMessage = "No Tailscale peer accepts files"
                }
            }
            isLoading = false
        }
    }

    func send(endpointTag: String, peer: TaildropTargetPeer) {
        guard !isSending, !files.isEmpty else { return }
        isSending = true
        let queued = files
        let progressHandler: @Sendable (Int32, Int64) -> Void = { [weak self] fileIndex, sentBytes in
            Task { @MainActor in
                self?.mutateFile(fileIndex) { file in
                    file.sentBytes = sentBytes
                }
            }
        }
        let fileCompletedHandler: @Sendable (Int32, Int64) -> Void = { [weak self] fileIndex, sentBytes in
            Task { @MainActor in
                self?.mutateFile(fileIndex) { file in
                    file.completed = true
                    file.sentBytes = sentBytes
                }
            }
        }
        let finishHandler: @Sendable (String?) -> Void = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.session = nil
                guard let message, !message.isEmpty else {
                    self.isFinished = true
                    return
                }
                self.isSending = false
                self.presentError(message)
            }
        }
        Task {
            do {
                session = try await Task.detached {
                    try TaildropSendSession.start(
                        endpointTag: endpointTag,
                        peerStableID: peer.stableID,
                        files: queued,
                        onProgress: progressHandler,
                        onFileCompleted: fileCompletedHandler,
                        onFinish: finishHandler
                    )
                }.value
            } catch {
                isSending = false
                presentError(error.localizedDescription)
            }
        }
    }

    private func presentError(_ message: String) {
        var state = AlertState(errorMessage: message)
        state.onDismiss = { [weak self] in
            self?.cancel()
        }
        alert = state
    }

    func cancel() {
        if let session {
            self.session = nil
            session.close()
        } else {
            for file in files {
                file.close()
            }
        }
        files = []
        onCancel?()
    }

    func openApplication() {
        onOpenApplication?(URL(string: "sing-box://taildrop")!)
        cancel()
    }

    private func mutateFile(_ fileIndex: Int32, _ mutate: (inout TaildropSendFile) -> Void) {
        let position = Int(fileIndex)
        guard files.indices.contains(position) else { return }
        mutate(&files[position])
    }

    private nonisolated static func open(_ attachments: [NSItemProvider]) async throws -> [TaildropSendFile] {
        var files: [TaildropSendFile] = []
        for attachment in attachments {
            do {
                try await files.append(open(attachment))
            } catch {
                for file in files {
                    file.close()
                }
                throw error
            }
        }
        return files
    }

    private nonisolated static func open(_ attachment: NSItemProvider) async throws -> TaildropSendFile {
        let contentType = attachment.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .item) && !type.conforms(to: .url)
        }
        if let contentType {
            return try await openFileRepresentation(attachment, typeIdentifier: contentType)
        }
        guard attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            throw NSError(domain: "ShareExtension", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "The shared item contains no file",
            ])
        }
        let url = try await loadFileURL(attachment)
        return try url.withSecurityScopedAccess {
            try TaildropSendFile(url, name: attachment.suggestedName ?? url.lastPathComponent)
        }
    }

    private nonisolated static func openFileRepresentation(
        _ attachment: NSItemProvider,
        typeIdentifier: String
    ) async throws -> TaildropSendFile {
        try await withCheckedThrowingContinuation { continuation in
            attachment.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: NSError(domain: "ShareExtension", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "The shared item contains no file",
                    ]))
                    return
                }
                do {
                    let file = try url.withSecurityScopedAccess {
                        try TaildropSendFile(url, name: attachment.suggestedName ?? url.lastPathComponent)
                    }
                    continuation.resume(returning: file)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func loadFileURL(_ attachment: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(throwing: NSError(domain: "ShareExtension", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "The shared item contains no file",
                ]))
            }
        }
    }
}
