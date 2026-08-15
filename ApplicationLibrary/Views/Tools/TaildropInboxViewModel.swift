import Foundation
import Libbox
import Library
import SwiftUI

#if !os(tvOS)

    public struct TaildropFileData: Identifiable, Equatable {
        public let name: String
        public let size: Int64
        public let senderName: String
        public let modifiedAt: Int64

        public var id: String {
            name
        }
    }

    public struct TaildropReceivingFileData: Identifiable, Equatable {
        public let name: String
        public let size: Int64
        public let receivedBytes: Int64
        public let senderID: String
        public let senderName: String

        public var id: String {
            senderID + "/" + name
        }
    }

    @MainActor
    public final class TaildropInboxViewModel: BaseViewModel {
        public struct Inbox: Equatable {
            public var files: [TaildropFileData] = []
            public var receiving: [TaildropReceivingFileData] = []
            public var received = false
        }

        @Published public private(set) var inboxes: [String: Inbox] = [:]

        private var subscriptions: [String: LibboxTaildropInboxSubscription] = [:]
        private var retainCounts: [String: Int] = [:]

        override public init() {
            super.init()
            try? FileManager.default.removeItem(at: Self.temporaryRoot)
        }

        public func inbox(endpointTag: String) -> Inbox {
            inboxes[endpointTag] ?? Inbox()
        }

        public func open(endpointTag: String) {
            retainCounts[endpointTag, default: 0] += 1
            guard retainCounts[endpointTag] == 1 else { return }
            let handler = InboxHandler(self, endpointTag: endpointTag)
            Task { [weak self] in
                do {
                    let subscription = try await Task.detached {
                        try CommandTarget.standaloneClient().subscribeTaildropInbox(endpointTag, handler: handler)
                    }.value
                    guard let self, retainCounts[endpointTag] != nil else {
                        try? subscription.close()
                        return
                    }
                    subscriptions[endpointTag] = subscription
                } catch {
                    guard let self, retainCounts[endpointTag] != nil else { return }
                    alert = AlertState(action: "subscribe Taildrop inbox", error: error)
                }
            }
            markRead(endpointTag: endpointTag)
        }

        public func close(endpointTag: String) {
            guard let count = retainCounts[endpointTag] else { return }
            if count > 1 {
                retainCounts[endpointTag] = count - 1
                return
            }
            retainCounts.removeValue(forKey: endpointTag)
            drop(endpointTag: endpointTag)
        }

        private func drop(endpointTag: String) {
            try? subscriptions.removeValue(forKey: endpointTag)?.close()
            inboxes.removeValue(forKey: endpointTag)
        }

        public func markRead(endpointTag: String) {
            Task {
                try? await Task.detached {
                    try CommandTarget.standaloneClient().markTaildropInboxRead(endpointTag)
                }.value
            }
        }

        public func cancelReceiving(endpointTag: String, senderID: String, name: String) async {
            do {
                try await Task.detached {
                    try CommandTarget.standaloneClient().cancelTaildropReceiving(endpointTag, senderID: senderID, name: name)
                }.value
            } catch {
                alert = AlertState(action: "cancel receiving file", error: error)
            }
        }

        public func delete(endpointTag: String, name: String) async {
            do {
                try await Task.detached {
                    try CommandTarget.standaloneClient().deleteTaildropFile(endpointTag, name: name)
                }.value
            } catch {
                alert = AlertState(action: "delete received file", error: error)
            }
        }

        public func deleteAll(endpointTag: String) async {
            let names = inbox(endpointTag: endpointTag).files.map(\.name)
            do {
                try await Task.detached {
                    let client = try CommandTarget.standaloneClient()
                    for name in names {
                        try client.deleteTaildropFile(endpointTag, name: name)
                    }
                }.value
            } catch {
                alert = AlertState(action: "delete received files", error: error)
            }
        }

        private static var temporaryRoot: URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("taildrop", isDirectory: true)
        }

        public static func removeTemporaryFile(_ url: URL) {
            let directory = url.deletingLastPathComponent()
            guard directory.deletingLastPathComponent().standardizedFileURL == temporaryRoot.standardizedFileURL else {
                return
            }
            try? FileManager.default.removeItem(at: directory)
        }

        public static func downloadToTemporaryDirectory(
            endpointTag: String,
            name: String,
            onProgress: @escaping @Sendable (Double) -> Void
        ) async throws -> URL {
            let directory = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent((name as NSString).lastPathComponent)
            let destinationPath = destination.path
            let completion = DownloadCompletion()
            let handler = DownloadHandler(onProgress: onProgress, completion: completion)
            let session = try await Task.detached {
                try CommandTarget.standaloneClient().downloadTaildropFile(
                    endpointTag,
                    name: name,
                    destinationPath: destinationPath,
                    handler: handler
                )
            }.value
            do {
                try await completion.wait()
            } catch {
                try? session.close()
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
            try? session.close()
            return destination
        }

        private final class DownloadCompletion: @unchecked Sendable {
            private let access = NSLock()
            private var continuation: CheckedContinuation<Void, Error>?
            private var result: Result<Void, Error>?

            func resolve(_ newResult: Result<Void, Error>) {
                access.lock()
                guard result == nil else {
                    access.unlock()
                    return
                }
                result = newResult
                let pending = continuation
                continuation = nil
                access.unlock()
                pending?.resume(with: newResult)
            }

            func wait() async throws {
                try await withCheckedThrowingContinuation { newContinuation in
                    access.lock()
                    if let result {
                        access.unlock()
                        newContinuation.resume(with: result)
                        return
                    }
                    continuation = newContinuation
                    access.unlock()
                }
            }
        }

        private final class DownloadHandler: NSObject, LibboxTaildropDownloadHandlerProtocol, @unchecked Sendable {
            private let progress: @Sendable (Double) -> Void
            private let completion: DownloadCompletion

            init(onProgress: @escaping @Sendable (Double) -> Void, completion: DownloadCompletion) {
                progress = onProgress
                self.completion = completion
            }

            func onProgress(_ downloaded: Int64, total: Int64) {
                guard total > 0 else { return }
                progress(min(Double(downloaded) / Double(total), 1))
            }

            func onFinish(_ errorMessage: String?) {
                guard let errorMessage, !errorMessage.isEmpty else {
                    completion.resolve(.success(()))
                    return
                }
                completion.resolve(.failure(NSError(domain: "Taildrop", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: errorMessage,
                ])))
            }
        }

        private final class InboxHandler: NSObject, LibboxTaildropInboxHandlerProtocol, @unchecked Sendable {
            private weak var viewModel: TaildropInboxViewModel?
            private let endpointTag: String

            init(_ viewModel: TaildropInboxViewModel?, endpointTag: String) {
                self.viewModel = viewModel
                self.endpointTag = endpointTag
            }

            func onInboxUpdate(_ update: LibboxTaildropInbox?) {
                guard let update else { return }
                var inbox = Inbox()
                inbox.received = true
                if let iterator = update.files() {
                    while iterator.hasNext() {
                        if let file = iterator.next() {
                            inbox.files.append(TaildropFileData(
                                name: file.name,
                                size: file.size,
                                senderName: file.senderName,
                                modifiedAt: file.modifiedAt
                            ))
                        }
                    }
                }
                if let iterator = update.receiving() {
                    while iterator.hasNext() {
                        if let file = iterator.next() {
                            inbox.receiving.append(TaildropReceivingFileData(
                                name: file.name,
                                size: file.size,
                                receivedBytes: file.receivedBytes,
                                senderID: file.senderID,
                                senderName: file.senderName
                            ))
                        }
                    }
                }
                DispatchQueue.main.async { [self] in
                    guard let viewModel, viewModel.retainCounts[endpointTag] != nil else { return }
                    viewModel.inboxes[endpointTag] = inbox
                    viewModel.markRead(endpointTag: endpointTag)
                }
            }

            func onError(_ message: String?) {
                DispatchQueue.main.async { [self] in
                    guard let viewModel, viewModel.retainCounts[endpointTag] != nil else { return }
                    viewModel.retainCounts.removeValue(forKey: endpointTag)
                    viewModel.drop(endpointTag: endpointTag)
                    if let message {
                        viewModel.alert = AlertState(errorMessage: message)
                    }
                }
            }
        }
    }

#endif
