import Foundation
import Libbox
import Library
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import QuickLook
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

#if !os(tvOS)

    @MainActor
    public struct TaildropView: View {
        @EnvironmentObject private var inbox: TaildropInboxViewModel
        @EnvironmentObject private var sendManager: TaildropSendManager
        @Environment(\.dismiss) private var dismiss
        @State private var alert: AlertState?
        @State private var preparingFile: String?
        @State private var preparingProgress: Double = 0
        @State private var exportDocument: TaildropFileDocument?
        @State private var exportFilename = ""
        @State private var exporterPresented = false
        @State private var exportedFile: URL?
        @State private var previewItem: TaildropPreviewItem?
        @State private var previewedFile: URL?
        #if os(macOS)
            @State private var sharePresented = false
            @State private var shareItemURL: URL?
        #endif

        let endpointTag: String

        public init(endpointTag: String) {
            self.endpointTag = endpointTag
        }

        private var sendingSessions: [TaildropSendManager.SendingSession] {
            sendManager.sessions(endpointTag: endpointTag)
        }

        private var inboxData: TaildropInboxViewModel.Inbox {
            inbox.inbox(endpointTag: endpointTag)
        }

        private var isEmptyPage: Bool {
            inboxData.received && inboxData.files.isEmpty && inboxData.receiving.isEmpty && sendingSessions.isEmpty
        }

        public var body: some View {
            FormView {
                if !sendingSessions.isEmpty {
                    Section("Send") {
                        ForEach(sendingSessions) { session in
                            ForEach(session.files) { file in
                                TaildropTransferRow(
                                    name: file.name,
                                    peerLabel: Text("to \(session.peerName)"),
                                    transferredBytes: file.sentBytes,
                                    totalBytes: file.size,
                                    finished: session.finished
                                ) {
                                    sendManager.cancel(sessionID: session.id)
                                }
                            }
                        }
                    }
                }
                if !inboxData.receiving.isEmpty {
                    Section("Receive") {
                        ForEach(inboxData.receiving) { file in
                            TaildropTransferRow(
                                name: file.name,
                                peerLabel: file.senderName.isEmpty ? nil : Text("from \(file.senderName)"),
                                transferredBytes: file.receivedBytes,
                                totalBytes: file.size
                            ) {
                                Task {
                                    await inbox.cancelReceiving(endpointTag: endpointTag, senderID: file.senderID, name: file.name)
                                }
                            }
                        }
                    }
                }
                if !inboxData.files.isEmpty {
                    Section("Files") {
                        ForEach(inboxData.files) { file in
                            fileRow(file)
                        }
                    }
                }
            }
            .navigationTitle("Taildrop")
            .toolbar {
                if !inboxData.files.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await inbox.deleteAll(endpointTag: endpointTag)
                            }
                        } label: {
                            Label("Delete All", systemImage: "trash.fill")
                        }
                    } label: {
                        Label("Others", systemImage: "line.3.horizontal.circle")
                    }
                }
            }
            .onAppear {
                inbox.open(endpointTag: endpointTag)
                presentNextFailedSession()
            }
            .onDisappear {
                inbox.close(endpointTag: endpointTag)
            }
            .onChangeCompat(of: isEmptyPage) { isEmpty in
                if isEmpty {
                    dismiss()
                }
            }
            .onChangeCompat(of: failedSessions.map(\.id)) { _ in
                presentNextFailedSession()
            }
            .onChangeCompat(of: alert == nil) { alertDismissed in
                if alertDismissed {
                    presentNextFailedSession()
                }
            }
            .alert($inbox.alert)
            .fileExporter(
                isPresented: $exporterPresented,
                document: exportDocument,
                contentType: .data,
                defaultFilename: exportFilename
            ) { result in
                exportDocument = nil
                let exported = exportedFile
                exportedFile = nil
                if let exported {
                    TaildropInboxViewModel.removeTemporaryFile(exported)
                }
                if case let .failure(error) = result {
                    alert = AlertState(action: "save received file", error: error)
                }
            }
            #if os(iOS)
            .sheet(item: $previewItem, onDismiss: {
                let previewed = previewedFile
                previewedFile = nil
                if let previewed {
                    TaildropInboxViewModel.removeTemporaryFile(previewed)
                }
            }) { item in
                TaildropQuickLookView(url: item.url)
                    .ignoresSafeArea()
            }
            #elseif os(macOS)
            .background(SharingServicePicker($sharePresented, $alert, $shareItemURL))
            #endif
            .alert($alert)
        }

        private var failedSessions: [TaildropSendManager.SendingSession] {
            sendingSessions.filter { $0.errorMessage != nil }
        }

        private func presentNextFailedSession() {
            guard alert == nil else { return }
            guard let session = failedSessions.first, let message = session.errorMessage else { return }
            var state = AlertState(errorMessage: message)
            state.onDismiss = {
                sendManager.cancel(sessionID: session.id)
            }
            alert = state
        }

        private func fileRow(_ file: TaildropFileData) -> some View {
            HStack {
                Button {
                    prepare(file.name, action: .open)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .lineLimit(1)
                            Text(fileSubtitle(file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if preparingFile == file.name {
                    ProgressView(value: preparingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 44, height: 32)
                } else {
                    Menu {
                        Button {
                            prepare(file.name, action: .save)
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            prepare(file.name, action: .share)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            Task {
                                await inbox.delete(endpointTag: endpointTag, name: file.name)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
                    .foregroundStyle(.secondary)
                }
            }
        }

        private func fileSubtitle(_ file: TaildropFileData) -> String {
            var components = [LibboxFormatBytes(file.size)]
            if !file.senderName.isEmpty {
                components.append(String(localized: "from \(file.senderName)"))
            }
            if file.modifiedAt > 0 {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                components.append(formatter.localizedString(
                    for: Date(timeIntervalSince1970: TimeInterval(file.modifiedAt)),
                    relativeTo: Date()
                ))
            }
            return components.joined(separator: " · ")
        }

        private enum FileAction {
            case save
            case open
            case share
        }

        private func prepare(_ name: String, action: FileAction) {
            guard preparingFile == nil else { return }
            preparingFile = name
            preparingProgress = 0
            Task {
                do {
                    let url = try await TaildropInboxViewModel.downloadToTemporaryDirectory(
                        endpointTag: endpointTag,
                        name: name,
                        onProgress: { progress in
                            Task { @MainActor in
                                preparingProgress = progress
                            }
                        }
                    )
                    preparingFile = nil
                    switch action {
                    case .save:
                        exportDocument = TaildropFileDocument(url: url)
                        exportFilename = url.lastPathComponent
                        exportedFile = url
                        exporterPresented = true
                    case .open:
                        #if os(iOS)
                            previewedFile = url
                            previewItem = TaildropPreviewItem(url: url)
                        #elseif os(macOS)
                            NSWorkspace.shared.open(url)
                        #endif
                    case .share:
                        #if os(iOS)
                            presentShareSheet(url)
                        #elseif os(macOS)
                            shareItemURL = url
                            sharePresented = true
                        #endif
                    }
                } catch {
                    preparingFile = nil
                    alert = AlertState(action: "download received file", error: error)
                }
            }
        }
    }

    private struct TaildropTransferRow: View {
        let name: String
        let peerLabel: Text?
        let transferredBytes: Int64
        let totalBytes: Int64
        var finished = false
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .lineLimit(1)
                        subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(finished ? Color.secondary : Color.red)
                }
                if !finished {
                    if totalBytes > 0 {
                        ProgressView(value: min(Double(transferredBytes) / Double(totalBytes), 1))
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }
        }

        private var subtitle: Text {
            guard let peerLabel else {
                return Text(progressText)
            }
            return Text(progressText) + Text(verbatim: " · ") + peerLabel
        }

        private var progressText: String {
            let transferred = ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
            guard totalBytes > 0 else {
                return transferred
            }
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            if finished, transferredBytes >= totalBytes {
                return total
            }
            return transferred + " / " + total
        }
    }

    private struct TaildropPreviewItem: Identifiable {
        let url: URL

        var id: String {
            url.path
        }
    }

    private struct TaildropFileDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            [.data]
        }

        private let url: URL

        init(url: URL) {
            self.url = url
        }

        init(configuration: ReadConfiguration) throws {
            guard let data = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: temporaryURL)
            url = temporaryURL
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            try FileWrapper(url: url)
        }
    }

    #if os(iOS)
        private struct TaildropQuickLookView: UIViewControllerRepresentable {
            let url: URL

            func makeUIViewController(context: Context) -> QLPreviewController {
                let controller = QLPreviewController()
                controller.dataSource = context.coordinator
                return controller
            }

            func updateUIViewController(_: QLPreviewController, context _: Context) {}

            func makeCoordinator() -> Coordinator {
                Coordinator(url: url)
            }

            final class Coordinator: NSObject, QLPreviewControllerDataSource {
                private let url: URL

                init(url: URL) {
                    self.url = url
                }

                func numberOfPreviewItems(in _: QLPreviewController) -> Int {
                    1
                }

                func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
                    url as NSURL
                }
            }
        }
    #endif

#endif
