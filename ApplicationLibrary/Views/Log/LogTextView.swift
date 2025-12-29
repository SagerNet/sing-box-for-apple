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

@MainActor
class LogCoordinator {
    var lastLogsCount: Int = 0
    var lastLog: LogEntry?
    var lastSearchText: String = ""
    var buildVersion: Int = 0
    var currentBuildTask: Task<Void, Never>?

    deinit {
        currentBuildTask?.cancel()
    }

    func shouldUpdate(logs: [LogEntry], searchText: String) -> UpdateStrategy {
        let currentCount = logs.count
        let searchChanged = searchText != lastSearchText

        // Check if nothing changed
        if currentCount == lastLogsCount, currentCount > 0, !searchChanged {
            if let lastLog = logs.last, let previousLastLog = self.lastLog {
                if lastLog.id == previousLastLog.id {
                    return .noUpdate
                }
            }
        }

        // Determine update strategy
        let strategy: UpdateStrategy
        if currentCount == 0 || searchChanged || lastLogsCount > currentCount {
            // Full rebuild needed
            strategy = .fullRebuild
        } else if currentCount > lastLogsCount {
            // Incremental update possible
            strategy = .incremental(from: lastLogsCount)
        } else {
            // Same count but different last log (shouldn't happen normally)
            strategy = .fullRebuild
        }

        lastLogsCount = currentCount
        lastLog = logs.last
        lastSearchText = searchText
        return strategy
    }

    #if os(iOS) || os(macOS)
        fileprivate func scheduleBuildTask(
            logs: [LogEntry],
            searchText: String,
            monoFont: PlatformFont,
            defaultColor: PlatformColor,
            startIndex: Int?,
            isViewValid: @escaping @MainActor () -> Bool,
            applyUpdate: @escaping @MainActor (NSAttributedString, Bool) -> Void
        ) {
            currentBuildTask?.cancel()
            buildVersion += 1
            let version = buildVersion

            currentBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let attributedString = try? await buildAttributedString(
                    logs: logs,
                    monoFont: monoFont,
                    defaultColor: defaultColor,
                    searchText: searchText,
                    startIndex: startIndex ?? 0
                ) else { return }
                await MainActor.run {
                    guard let self, isViewValid() else { return }
                    guard self.buildVersion == version else { return }
                    applyUpdate(attributedString, startIndex != nil)
                    self.currentBuildTask = nil
                }
            }
        }
    #endif

    enum UpdateStrategy {
        case noUpdate
        case fullRebuild
        case incremental(from: Int)
    }
}

#if os(iOS) || os(macOS)
    private func buildAttributedString(logs: [LogEntry], monoFont: PlatformFont, defaultColor: PlatformColor, searchText: String, startIndex: Int = 0) async throws -> NSAttributedString {
        let result = NSMutableAttributedString()
        let highlightColor: PlatformColor = .systemYellow
        let cancellationCheckInterval = 50

        let logsToProcess = logs[startIndex...]

        for (offset, log) in logsToProcess.enumerated() {
            if offset % cancellationCheckInterval == 0 {
                try Task.checkCancellation()
            }

            let attributedString = ANSIColors.parseAnsiString(log.message)
            let nsAttributedString = NSMutableAttributedString(string: String(attributedString.characters))

            for run in attributedString.runs {
                let range = NSRange(run.range, in: attributedString)
                let color = run.foregroundColor.map { PlatformColor($0) } ?? defaultColor

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

            result.append(nsAttributedString)

            let isLastLog = (startIndex + offset) == (logs.count - 1)
            if !isLastLog {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .foregroundColor: defaultColor,
                    .font: monoFont,
                ]))
            }
        }
        return result
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
            let updateStrategy = context.coordinator.shouldUpdate(logs: logs, searchText: searchText)

            let startIndex: Int?
            switch updateStrategy {
            case .noUpdate:
                return
            case .fullRebuild:
                startIndex = nil
            case let .incremental(from: index):
                startIndex = index
            }

            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleBuildTask(
                logs: logs,
                searchText: searchText,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                startIndex: startIndex,
                isViewValid: { [weak textView] in textView?.window != nil },
                applyUpdate: { [weak textView] attributedString, isIncremental in
                    guard let textView else { return }
                    if isIncremental {
                        let textStorage = textView.textStorage
                        if textStorage.length > 0 {
                            textStorage.append(NSAttributedString(string: "\n", attributes: [
                                .foregroundColor: Self.defaultColor,
                                .font: Self.monoFont,
                            ]))
                        }
                        textStorage.append(attributedString)
                    } else {
                        textView.attributedText = attributedString
                    }
                    if shouldAutoScroll {
                        Self.scrollToBottom(textView)
                    }
                }
            )
        }

        private static func scrollToBottom(_ textView: UITextView) {
            textView.layoutManager.ensureLayout(for: textView.textContainer)
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

            let textView = NSTextView()
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

            let updateStrategy = context.coordinator.shouldUpdate(logs: logs, searchText: searchText)

            let startIndex: Int?
            switch updateStrategy {
            case .noUpdate:
                return
            case .fullRebuild:
                startIndex = nil
            case let .incremental(from: index):
                startIndex = index
            }

            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleBuildTask(
                logs: logs,
                searchText: searchText,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                startIndex: startIndex,
                isViewValid: { [weak textView] in textView?.window != nil },
                applyUpdate: { [weak textView, weak textStorage] attributedString, isIncremental in
                    guard let textView, let textStorage else { return }
                    if isIncremental {
                        if textStorage.length > 0 {
                            textStorage.append(NSAttributedString(string: "\n", attributes: [
                                .foregroundColor: Self.defaultColor,
                                .font: Self.monoFont,
                            ]))
                        }
                        textStorage.append(attributedString)
                    } else {
                        textStorage.setAttributedString(attributedString)
                    }
                    if let textContainer = textView.textContainer {
                        textView.layoutManager?.ensureLayout(for: textContainer)
                    }
                    if shouldAutoScroll {
                        textView.scrollToEndOfDocument(nil)
                    }
                }
            )
        }

        func makeCoordinator() -> LogCoordinator {
            LogCoordinator()
        }
    }
#endif
