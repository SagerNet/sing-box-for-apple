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

class LogCoordinator {
    var lastLogsCount: Int = 0
    var lastLog: LogEntry?
    var lastSearchText: String = ""
    var cachedAttributedString: NSAttributedString?

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
            cachedAttributedString = nil
        } else if currentCount > lastLogsCount {
            // Incremental update possible
            strategy = .incremental(from: lastLogsCount)
        } else {
            // Same count but different last log (shouldn't happen normally)
            strategy = .fullRebuild
            cachedAttributedString = nil
        }

        lastLogsCount = currentCount
        lastLog = logs.last
        lastSearchText = searchText
        return strategy
    }

    enum UpdateStrategy {
        case noUpdate
        case fullRebuild
        case incremental(from: Int)
    }
}

#if os(iOS) || os(macOS)
    private func buildAttributedString(logs: [LogEntry], monoFont: PlatformFont, defaultColor: PlatformColor, searchText: String, baseAttributedString: NSAttributedString? = nil, startIndex: Int = 0) -> NSAttributedString {
        let result: NSMutableAttributedString
        let highlightColor: PlatformColor = .systemYellow

        if let base = baseAttributedString {
            result = NSMutableAttributedString(attributedString: base)
            // Add newline separator if appending to existing content
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .foregroundColor: defaultColor,
                    .font: monoFont,
                ]))
            }
        } else {
            result = NSMutableAttributedString()
        }

        let logsToProcess = logs[startIndex...]

        for (offset, log) in logsToProcess.enumerated() {
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
    struct LogTextViewIOS: View {
        let logs: [LogEntry]
        let font: Font
        let shouldAutoScroll: Bool
        let searchText: String

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LogUITextView(logs: logs, searchText: searchText)
                        .font(font)
                        // Explicit height ensures navigation bar large title collapse animation works correctly with UITextView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                        .id("logContent")
                }
                .onAppear {
                    if shouldAutoScroll {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChangeCompat(of: logs.count) { _ in
                    if shouldAutoScroll {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }

        private func scrollToBottom(proxy: ScrollViewProxy) {
            DispatchQueue.main.async {
                proxy.scrollTo("logContent", anchor: .bottom)
            }
        }
    }

    struct LogUITextView: UIViewRepresentable {
        let logs: [LogEntry]
        let searchText: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        private static let defaultColor = UIColor.label

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = Self.defaultColor
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // Low hugging priority allows expansion to fill available space for proper ScrollView integration
            textView.setContentHuggingPriority(.defaultLow, for: .vertical)
            return textView
        }

        func updateUIView(_ textView: UITextView, context: Context) {
            let updateStrategy = context.coordinator.shouldUpdate(logs: logs, searchText: searchText)

            switch updateStrategy {
            case .noUpdate:
                return
            case .fullRebuild:
                let attributedString = buildAttributedString(logs: logs, monoFont: Self.monoFont, defaultColor: Self.defaultColor, searchText: searchText)
                context.coordinator.cachedAttributedString = attributedString
                textView.attributedText = attributedString
            case let .incremental(from: startIndex):
                let attributedString = buildAttributedString(logs: logs, monoFont: Self.monoFont, defaultColor: Self.defaultColor, searchText: searchText, baseAttributedString: context.coordinator.cachedAttributedString, startIndex: startIndex)
                context.coordinator.cachedAttributedString = attributedString
                textView.attributedText = attributedString
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
            }

            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }

            let lastCount = context.coordinator.lastLogsCount
            let updateStrategy = context.coordinator.shouldUpdate(logs: logs, searchText: searchText)

            switch updateStrategy {
            case .noUpdate:
                return
            case .fullRebuild:
                let attributedText = buildAttributedString(logs: logs, monoFont: Self.monoFont, defaultColor: Self.defaultColor, searchText: searchText)
                context.coordinator.cachedAttributedString = attributedText
                textView.textStorage?.setAttributedString(attributedText)
            case let .incremental(from: startIndex):
                let attributedText = buildAttributedString(logs: logs, monoFont: Self.monoFont, defaultColor: Self.defaultColor, searchText: searchText, baseAttributedString: context.coordinator.cachedAttributedString, startIndex: startIndex)
                context.coordinator.cachedAttributedString = attributedText
                textView.textStorage?.setAttributedString(attributedText)
            }

            let shouldScroll = shouldAutoScroll && logs.count != lastCount
            if shouldScroll {
                DispatchQueue.main.async {
                    textView.scrollToEndOfDocument(nil)
                }
            }
        }

        func makeCoordinator() -> LogCoordinator {
            LogCoordinator()
        }
    }
#endif
