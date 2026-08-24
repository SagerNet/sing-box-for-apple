import Foundation
import Library
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#endif

#if !os(tvOS)

    @MainActor
    public final class TaildropSendManager: ObservableObject {
        public struct SendingSession: Identifiable {
            public let id: UUID
            public let endpointTag: String
            public let peerName: String
            public var files: [TaildropSendFile]
            public var finished = false
            public var errorMessage: String?
        }

        @Published public private(set) var sendingSessions: [SendingSession] = []

        private var activeSessions: [UUID: TaildropSendSession] = [:]

        public init() {}

        public func sessions(endpointTag: String) -> [SendingSession] {
            sendingSessions.filter { $0.endpointTag == endpointTag }
        }

        public func hasSessions(endpointTag: String) -> Bool {
            sendingSessions.contains { $0.endpointTag == endpointTag }
        }

        public func isSending(endpointTag: String) -> Bool {
            sendingSessions.contains { $0.endpointTag == endpointTag && !$0.finished }
        }

        public func hasFailedSessions(endpointTag: String) -> Bool {
            sendingSessions.contains { $0.endpointTag == endpointTag && $0.errorMessage != nil }
        }

        public var failedSessionCount: Int {
            sendingSessions.filter { $0.errorMessage != nil }.count
        }

        public func start(endpointTag: String, peerStableID: String, peerName: String, urls: [URL]) async throws {
            let opened = try await Task.detached {
                try Self.open(urls)
            }.value
            let sessionID = UUID()
            sendingSessions.append(SendingSession(
                id: sessionID,
                endpointTag: endpointTag,
                peerName: peerName,
                files: opened
            ))
            let onProgress: @Sendable (Int32, Int64) -> Void = { [weak self] fileIndex, sentBytes in
                Task { @MainActor in
                    self?.mutateFile(sessionID: sessionID, fileIndex: fileIndex) { file in
                        file.sentBytes = sentBytes
                    }
                }
            }
            let onFileCompleted: @Sendable (Int32, Int64) -> Void = { [weak self] fileIndex, sentBytes in
                Task { @MainActor in
                    self?.mutateFile(sessionID: sessionID, fileIndex: fileIndex) { file in
                        file.completed = true
                        file.sentBytes = sentBytes
                    }
                }
            }
            let onFinish: @Sendable (String?) -> Void = { [weak self] errorMessage in
                Task { @MainActor in
                    self?.finish(sessionID: sessionID, errorMessage: errorMessage)
                }
            }
            do {
                activeSessions[sessionID] = try await Task.detached {
                    try TaildropSendSession.start(
                        endpointTag: endpointTag,
                        peerStableID: peerStableID,
                        files: opened,
                        onProgress: onProgress,
                        onFileCompleted: onFileCompleted,
                        onFinish: onFinish
                    )
                }.value
            } catch {
                sendingSessions.removeAll { $0.id == sessionID }
                for file in opened {
                    file.close()
                }
                throw error
            }
        }

        public func cancel(sessionID: UUID) {
            activeSessions.removeValue(forKey: sessionID)?.close()
            sendingSessions.removeAll { $0.id == sessionID }
        }

        private func finish(sessionID: UUID, errorMessage message: String?) {
            activeSessions.removeValue(forKey: sessionID)
            let position = sendingSessions.firstIndex { $0.id == sessionID }
            guard let position else { return }
            sendingSessions[position].finished = true
            if let message, !message.isEmpty {
                sendingSessions[position].errorMessage = message
            }
        }

        private func mutateFile(sessionID: UUID, fileIndex: Int32, _ mutate: (inout TaildropSendFile) -> Void) {
            let sessionPosition = sendingSessions.firstIndex { $0.id == sessionID }
            guard let sessionPosition else { return }
            let filePosition = Int(fileIndex)
            guard sendingSessions[sessionPosition].files.indices.contains(filePosition) else { return }
            mutate(&sendingSessions[sessionPosition].files[filePosition])
        }

        private nonisolated static func open(_ urls: [URL]) throws -> [TaildropSendFile] {
            var opened: [TaildropSendFile] = []
            for url in urls {
                do {
                    try opened.append(url.withSecurityScopedAccess {
                        try TaildropSendFile(url, name: url.lastPathComponent)
                    })
                } catch {
                    for file in opened {
                        file.close()
                    }
                    throw error
                }
            }
            return opened
        }
    }

    @MainActor
    public struct TaildropSendZone: View {
        private let endpointTag: String
        private let peerStableID: String
        private let peerName: String

        @EnvironmentObject private var sendManager: TaildropSendManager
        @State private var importerPresented = false
        @State private var dropTargeted = false
        @State private var navigationTag: String?
        @State private var alert: AlertState?

        public init(endpointTag: String, peerStableID: String, peerName: String) {
            self.endpointTag = endpointTag
            self.peerStableID = peerStableID
            self.peerName = peerName
        }

        public var body: some View {
            zone
                .fileImporter(
                    isPresented: $importerPresented,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case let .success(urls):
                        send(urls)
                    case let .failure(error):
                        guard (error as? CocoaError)?.code != .userCancelled else { return }
                        alert = AlertState(action: "select files", error: error)
                    }
                }
                .background {
                    NavigationDestinationCompat(isPresented: Binding(
                        get: { navigationTag != nil },
                        set: { newValue in
                            if !newValue {
                                navigationTag = nil
                            }
                        }
                    )) {
                        if let navigationTag {
                            TaildropView(endpointTag: navigationTag)
                        }
                    }
                    .opacity(0)
                }
                .alert($alert)
        }

        private var label: some View {
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                #if os(macOS)
                    Text("Drop files here to send, or click to select")
                #else
                    Text("Drop files here to send, or tap to select")
                #endif
            }
            .font(.caption)
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }

        #if os(macOS)
            private var zone: some View {
                Button {
                    importerPresented = true
                } label: {
                    label
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    drop(providers)
                }
            }

            private func drop(_ providers: [NSItemProvider]) -> Bool {
                let eligible = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
                if eligible.isEmpty {
                    return false
                }
                Task {
                    var urls: [URL] = []
                    for provider in eligible {
                        let url = try? await loadFileURL(provider)
                        if let url {
                            urls.append(url)
                        }
                    }
                    send(urls)
                }
                return true
            }

            private nonisolated func loadFileURL(_ provider: NSItemProvider) async throws -> URL {
                try await withCheckedThrowingContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, error in
                        if let url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
                        }
                    }
                }
            }
        #else
            private var zone: some View {
                label
                    .background {
                        TaildropDropArea(
                            onTargeted: { targeted in
                                dropTargeted = targeted
                            },
                            onTap: {
                                importerPresented = true
                            },
                            onFiles: { files, firstError in
                                if files.isEmpty, let firstError {
                                    alert = AlertState(action: "receive dropped files", error: firstError)
                                    return
                                }
                                send(files.map(\.url), temporaryDirectories: files.compactMap(\.temporaryDirectory))
                            }
                        )
                    }
            }
        #endif

        private func send(_ urls: [URL], temporaryDirectories: [URL] = []) {
            let removeTemporaryDirectories = {
                for directory in temporaryDirectories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
            if urls.isEmpty {
                removeTemporaryDirectories()
                return
            }
            Task {
                do {
                    try await sendManager.start(
                        endpointTag: endpointTag,
                        peerStableID: peerStableID,
                        peerName: peerName,
                        urls: urls
                    )
                    navigationTag = endpointTag
                } catch {
                    alert = AlertState(action: "send files", error: error)
                }
                removeTemporaryDirectories()
            }
        }
    }

    #if os(iOS)
        struct TaildropDroppedFile {
            let url: URL
            let temporaryDirectory: URL?
        }

        /// SwiftUI's onDrop and dropDestination inside a Form or List row never receive
        /// drop sessions originating from other applications (they work for in-app drags
        /// only); a UIKit UIDropInteraction on the same row receives them normally.
        private struct TaildropDropArea: UIViewRepresentable {
            let onTargeted: (Bool) -> Void
            let onTap: () -> Void
            let onFiles: ([TaildropDroppedFile], Error?) -> Void

            func makeUIView(context _: Context) -> TaildropDropView {
                let view = TaildropDropView()
                view.onTargeted = onTargeted
                view.onTap = onTap
                view.onFiles = onFiles
                return view
            }

            func updateUIView(_ view: TaildropDropView, context _: Context) {
                view.onTargeted = onTargeted
                view.onTap = onTap
                view.onFiles = onFiles
            }
        }

        final class TaildropDropView: UIView, UIDropInteractionDelegate {
            var onTargeted: ((Bool) -> Void)?
            var onTap: (() -> Void)?
            var onFiles: (([TaildropDroppedFile], Error?) -> Void)?

            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = .clear
                addInteraction(UIDropInteraction(delegate: self))
                addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            @objc private func handleTap() {
                onTap?()
            }

            func dropInteraction(_: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
                session.hasItemsConforming(toTypeIdentifiers: [UTType.item.identifier])
            }

            func dropInteraction(_: UIDropInteraction, sessionDidEnter _: UIDropSession) {
                onTargeted?(true)
            }

            func dropInteraction(_: UIDropInteraction, sessionDidExit _: UIDropSession) {
                onTargeted?(false)
            }

            func dropInteraction(_: UIDropInteraction, sessionDidEnd _: UIDropSession) {
                onTargeted?(false)
            }

            func dropInteraction(_: UIDropInteraction, sessionDidUpdate _: UIDropSession) -> UIDropProposal {
                UIDropProposal(operation: .copy)
            }

            func dropInteraction(_: UIDropInteraction, performDrop session: UIDropSession) {
                let loadGroup = DispatchGroup()
                let resultAccess = DispatchQueue(label: "\(AppConfiguration.packageName).taildrop-drop")
                var files: [TaildropDroppedFile] = []
                var firstError: Error?
                let reportError = { (error: Error) in
                    resultAccess.sync {
                        if firstError == nil {
                            firstError = error
                        }
                    }
                }
                for item in session.items {
                    let provider = item.itemProvider
                    let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
                        UTType(identifier)?.conforms(to: .item) == true
                    } ?? provider.registeredTypeIdentifiers.first
                    guard let typeIdentifier else { continue }
                    loadGroup.enter()
                    _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
                        defer { loadGroup.leave() }
                        guard let url else {
                            reportError(error ?? CocoaError(.fileNoSuchFile))
                            return
                        }
                        if isInPlace {
                            resultAccess.sync {
                                files.append(TaildropDroppedFile(url: url, temporaryDirectory: nil))
                            }
                            return
                        }
                        do {
                            let directory = FileManager.default.temporaryDirectory
                                .appendingPathComponent("taildrop-\(UUID().uuidString)", isDirectory: true)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            let copied = directory.appendingPathComponent(url.lastPathComponent)
                            try FileManager.default.copyItem(at: url, to: copied)
                            resultAccess.sync {
                                files.append(TaildropDroppedFile(url: copied, temporaryDirectory: directory))
                            }
                        } catch let copyError {
                            reportError(copyError)
                        }
                    }
                }
                loadGroup.notify(queue: .main) { [weak self] in
                    self?.onFiles?(files, firstError)
                }
            }
        }
    #endif

#endif
