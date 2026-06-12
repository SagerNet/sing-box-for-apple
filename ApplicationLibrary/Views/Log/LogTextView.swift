import Foundation
import Library
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct LogTextView: View {
    let logs: [LogEntry]
    let font: Font
    let shouldAutoScroll: Bool
    let searchText: String

    var body: some View {
        #if os(iOS)
            LogTextViewIOS(logs: logs, font: font, shouldAutoScroll: shouldAutoScroll, searchText: searchText)
        #elseif os(macOS)
            LogTextViewMacOS(logs: logs, font: font, shouldAutoScroll: shouldAutoScroll, searchText: searchText)
        #endif
    }
}

#if os(iOS) || os(macOS)
    /// The logs array is a sliding window over a trimmed stream: entries are appended at
    /// the tail and dropped from the head. Updates are applied as a prefix deletion plus
    /// a tail append, so the text storage is never rebuilt while streaming.
    private struct TextUpdate {
        var replaceAll: Bool
        var deletePrefixLength: Int
        var insertSeparator: Bool
        var appended: NSAttributedString
    }

    @MainActor
    class LogCoordinator {
        // State of the content currently applied to the text storage. Only mutated
        // when an update is actually applied, so cancelled builds cannot desync it.
        fileprivate var appliedIDs: [UUID] = []
        fileprivate var appliedLineLengths: [Int] = []
        fileprivate var appliedSearchText = ""
        fileprivate var appliedColorHash: Int?
        private var buildVersion = 0
        private var currentBuildTask: Task<Void, Never>?

        deinit {
            currentBuildTask?.cancel()
        }

        enum UpdateStrategy {
            case noUpdate
            case fullRebuild
            case incremental(appendFrom: Int, dropFirst: Int)
        }

        fileprivate func strategy(logs: [LogEntry], searchText: String, backgroundColorHash: Int) -> UpdateStrategy {
            if appliedColorHash != backgroundColorHash || searchText != appliedSearchText {
                return .fullRebuild
            }
            if logs.isEmpty {
                return appliedIDs.isEmpty ? .noUpdate : .fullRebuild
            }
            guard let lastAppliedID = appliedIDs.last else {
                return .fullRebuild
            }
            guard let overlapIndex = logs.lastIndex(where: { $0.id == lastAppliedID }) else {
                return .fullRebuild
            }
            let dropFirst = appliedIDs.count - (overlapIndex + 1)
            guard dropFirst >= 0 else {
                return .fullRebuild
            }
            if dropFirst == 0, overlapIndex == logs.count - 1 {
                return .noUpdate
            }
            return .incremental(appendFrom: overlapIndex + 1, dropFirst: dropFirst)
        }

        fileprivate func scheduleUpdate(
            logs: [LogEntry],
            strategy: UpdateStrategy,
            searchText: String,
            backgroundColorHash: Int,
            monoFont: PlatformFont,
            defaultColor: PlatformColor,
            backgroundColor: PlatformColor,
            applyUpdate: @escaping @MainActor (TextUpdate) -> Void
        ) {
            let startIndex: Int
            let dropFirst: Int
            let replaceAll: Bool
            switch strategy {
            case .noUpdate:
                return
            case .fullRebuild:
                startIndex = 0
                dropFirst = 0
                replaceAll = true
            case let .incremental(appendFrom, drop):
                startIndex = appendFrom
                dropFirst = drop
                replaceAll = false
            }

            currentBuildTask?.cancel()
            buildVersion += 1
            let version = buildVersion
            let newIDs = logs.map(\.id)

            currentBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let built = try? await buildAttributedString(
                    logs: logs,
                    monoFont: monoFont,
                    defaultColor: defaultColor,
                    backgroundColor: backgroundColor,
                    searchText: searchText,
                    startIndex: startIndex
                ) else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.buildVersion == version else { return }
                    let update: TextUpdate
                    let newLineLengths: [Int]
                    if replaceAll {
                        update = TextUpdate(
                            replaceAll: true,
                            deletePrefixLength: 0,
                            insertSeparator: false,
                            appended: built.string
                        )
                        newLineLengths = built.lineLengths
                    } else {
                        var deleteLength = 0
                        if dropFirst > 0 {
                            deleteLength = self.appliedLineLengths.prefix(dropFirst).reduce(0, +) + dropFirst
                        }
                        update = TextUpdate(
                            replaceAll: false,
                            deletePrefixLength: deleteLength,
                            insertSeparator: built.string.length > 0,
                            appended: built.string
                        )
                        newLineLengths = Array(self.appliedLineLengths.dropFirst(dropFirst)) + built.lineLengths
                    }
                    applyUpdate(update)
                    self.appliedIDs = newIDs
                    self.appliedLineLengths = newLineLengths
                    self.appliedSearchText = searchText
                    self.appliedColorHash = backgroundColorHash
                    self.currentBuildTask = nil
                }
            }
        }
    }

    private func buildAttributedString(
        logs: [LogEntry],
        monoFont: PlatformFont,
        defaultColor: PlatformColor,
        backgroundColor: PlatformColor,
        searchText: String,
        startIndex: Int
    ) async throws -> (string: NSAttributedString, lineLengths: [Int]) {
        let result = NSMutableAttributedString()
        var lineLengths: [Int] = []
        let highlightColor: PlatformColor = .systemYellow
        let cancellationCheckInterval = 50

        for (offset, log) in logs[startIndex...].enumerated() {
            if offset % cancellationCheckInterval == 0 {
                try Task.checkCancellation()
            }

            let attributedString = ANSIColors.parseAnsiString(log.message)
            let nsAttributedString = NSMutableAttributedString(string: String(attributedString.characters))

            for run in attributedString.runs {
                let range = NSRange(run.range, in: attributedString)
                var color = run.foregroundColor.map { PlatformColor($0) } ?? defaultColor
                color = color.adjustedForContrast(against: backgroundColor)

                nsAttributedString.addAttribute(.foregroundColor, value: color, range: range)
                nsAttributedString.addAttribute(.font, value: monoFont, range: range)
            }

            if !searchText.isEmpty {
                let fullString = nsAttributedString.string
                var searchRange = fullString.startIndex ..< fullString.endIndex

                while let range = fullString.range(of: searchText, range: searchRange) {
                    let nsRange = NSRange(range, in: fullString)
                    nsAttributedString.addAttribute(.backgroundColor, value: highlightColor, range: nsRange)
                    searchRange = range.upperBound ..< fullString.endIndex
                }
            }

            lineLengths.append(nsAttributedString.length)
            if offset > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .foregroundColor: defaultColor,
                    .font: monoFont,
                ]))
            }
            result.append(nsAttributedString)
        }
        return (result, lineLengths)
    }

    private extension NSTextStorage {
        func apply(_ update: TextUpdate, separatorAttributes: [NSAttributedString.Key: Any]) {
            if update.deletePrefixLength > 0 {
                deleteCharacters(in: NSRange(location: 0, length: min(update.deletePrefixLength, length)))
            }
            if update.appended.length > 0 {
                if update.insertSeparator, length > 0 {
                    append(NSAttributedString(string: "\n", attributes: separatorAttributes))
                }
                append(update.appended)
            }
        }
    }

    #if os(iOS)
        private typealias PlatformFont = UIFont
        private typealias PlatformColor = UIColor
    #elseif os(macOS)
        private typealias PlatformFont = NSFont
        private typealias PlatformColor = NSColor
    #endif
#endif

#if os(iOS)
    struct LogTextViewIOS: UIViewRepresentable {
        let logs: [LogEntry]
        let font: Font
        let shouldAutoScroll: Bool
        let searchText: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        private static let defaultColor = UIColor.label

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = true
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = Self.defaultColor
            return textView
        }

        func updateUIView(_ textView: UITextView, context: Context) {
            let backgroundColor = UIColor.systemBackground.resolvedColor(with: textView.traitCollection)
            let backgroundColorHash = backgroundColor.hash

            let strategy = context.coordinator.strategy(logs: logs, searchText: searchText, backgroundColorHash: backgroundColorHash)
            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleUpdate(
                logs: logs,
                strategy: strategy,
                searchText: searchText,
                backgroundColorHash: backgroundColorHash,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                backgroundColor: backgroundColor,
                applyUpdate: { [weak textView] update in
                    guard let textView else { return }
                    let wasPinnedToBottom = Self.isPinnedToBottom(textView)
                    if update.replaceAll {
                        textView.attributedText = update.appended
                    } else {
                        textView.textStorage.apply(update, separatorAttributes: [
                            .foregroundColor: Self.defaultColor,
                            .font: Self.monoFont,
                        ])
                    }
                    if shouldAutoScroll, update.replaceAll || wasPinnedToBottom {
                        Self.scrollToBottom(textView)
                    }
                }
            )
        }

        private static func isPinnedToBottom(_ textView: UITextView) -> Bool {
            if textView.isTracking || textView.isDragging || textView.isDecelerating {
                return false
            }
            let bottom = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
            return bottom <= 0 || textView.contentOffset.y >= bottom - 44
        }

        /// Must not touch `layoutManager` here: accessing it opts the view out of
        /// TextKit 2, and TextKit 1 invalidates layout for the entire document on
        /// every head trim. TextKit 2 only lays out the visible viewport, so both
        /// appends and trims stay O(visible) regardless of log size.
        private static func scrollToBottom(_ textView: UITextView) {
            if #available(iOS 16.0, *), let textLayoutManager = textView.textLayoutManager {
                textLayoutManager.ensureLayout(for: NSTextRange(location: textLayoutManager.documentRange.endLocation))
            }
            textView.layoutIfNeeded()
            let bottom = textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom
            if bottom > 0 {
                textView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
        }

        func makeCoordinator() -> LogCoordinator {
            LogCoordinator()
        }
    }
#endif

#if os(macOS)
    struct LogTextViewMacOS: NSViewRepresentable {
        let logs: [LogEntry]
        let font: Font
        let shouldAutoScroll: Bool
        let searchText: String

        private static let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        private static let defaultColor = NSColor.labelColor

        func makeNSView(context _: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // TextKit 2: viewport-based layout keeps head trims and appends
            // O(visible) instead of re-laying-out the whole document.
            let textView = NSTextView(usingTextLayoutManager: true)
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 16, height: 16)
            textView.font = Self.monoFont
            textView.textColor = Self.defaultColor
            textView.autoresizingMask = [.width]

            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                textContainer.lineFragmentPadding = 0
            }

            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            let backgroundColor = NSColor.textBackgroundColor
            let backgroundColorHash = backgroundColor.hash

            let strategy = context.coordinator.strategy(logs: logs, searchText: searchText, backgroundColorHash: backgroundColorHash)
            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleUpdate(
                logs: logs,
                strategy: strategy,
                searchText: searchText,
                backgroundColorHash: backgroundColorHash,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                backgroundColor: backgroundColor,
                applyUpdate: { [weak textView, weak textStorage] update in
                    guard let textView, let textStorage else { return }
                    let wasPinnedToBottom = Self.isPinnedToBottom(textView)
                    if update.replaceAll {
                        textStorage.setAttributedString(update.appended)
                    } else {
                        textStorage.apply(update, separatorAttributes: [
                            .foregroundColor: Self.defaultColor,
                            .font: Self.monoFont,
                        ])
                    }
                    if shouldAutoScroll, update.replaceAll || wasPinnedToBottom {
                        // `layoutManager` must stay untouched (it would force a fallback
                        // to TextKit 1); laying out just the document end is enough for
                        // an accurate scroll target.
                        if let textLayoutManager = textView.textLayoutManager {
                            textLayoutManager.ensureLayout(for: NSTextRange(location: textLayoutManager.documentRange.endLocation))
                        }
                        textView.scrollToEndOfDocument(nil)
                    }
                }
            )
        }

        private static func isPinnedToBottom(_ textView: NSTextView) -> Bool {
            guard let scrollView = textView.enclosingScrollView else { return true }
            let visibleRect = scrollView.contentView.bounds
            return visibleRect.maxY >= textView.frame.height - 44
        }

        func makeCoordinator() -> LogCoordinator {
            LogCoordinator()
        }
    }
#endif
