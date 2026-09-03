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

    #if os(iOS)
        @Environment(\.logBottomInset) private var bottomInset
    #endif

    var body: some View {
        #if os(iOS)
            LogTextViewIOS(
                logs: logs,
                font: font,
                shouldAutoScroll: shouldAutoScroll,
                searchText: searchText,
                bottomInset: bottomInset
            )
        #elseif os(macOS)
            LogTextViewMacOS(logs: logs, font: font, shouldAutoScroll: shouldAutoScroll, searchText: searchText)
        #endif
    }
}

#if os(iOS) || os(macOS)
    /// Every update replaces the whole document instead of editing the text storage in
    /// place, because TextKit 2 never releases the layout state belonging to content an
    /// edit removed or invalidated.
    ///
    /// Measured on the iOS 27.0 simulator (24A434) by streaming 20 lines per cycle into a
    /// 1000-line window — append at the tail plus `deleteCharacters` at the head, so the
    /// document stays a constant ~115 KB:
    ///
    /// - UITextView on TextKit 2: +166 MB over 300 cycles (~28 KB per log line), +3.5 GB
    ///   over 4000 cycles. Nothing is returned when the edits stop, when the text view is
    ///   released, or under memory pressure.
    /// - The same edits on the same view forced onto TextKit 1, by reading `layoutManager`
    ///   before any content: flat.
    /// - The same edits on a bare `NSTextContentStorage` + `NSTextLayoutManager` +
    ///   `NSTextContainer` driven by `ensureLayout(for:)`, with no text view in the picture
    ///   at all: +121 MB over 300 cycles.
    /// - Replacing the whole string every cycle: flat, 17 -> 16 MB over 600 cycles.
    ///
    /// So the leak is in TextKit 2 itself rather than in the text view, and the head
    /// deletion is not what triggers it — append-only edits grow the same way, faster per
    /// line. Wrapping the edits in `beginEditing`/`endEditing` or
    /// `NSTextContentManager.performEditingTransaction` changes nothing.
    /// `NSTextLayoutManager` ships in UIFoundation, so AppKit behaves identically.
    ///
    /// In-place edits also drift `contentSize.height` upward for a window whose line count
    /// never changes (39413 -> 85817 pt over 4000 cycles), leaving the viewport parked past
    /// the real end of the document. A field report from 1.15.0-alpha.5 on iOS 27.0 (24A437)
    /// had the main thread spending 4+ seconds inside
    /// `-[NSTextLayoutManager _estimatedTextLocationForVerticalOffset:...]` while the
    /// footprint climbed from 791 MB to 1.49 GB, until jetsam killed the app.
    ///
    /// A rebuild costs ~30 ms for a 1000-line window, and it already runs off the main
    /// thread.
    @MainActor
    class LogCoordinator {
        // State of the content currently applied to the text storage. Only mutated
        // when an update is actually applied, so cancelled builds cannot desync it.
        private var appliedIDs: [UUID] = []
        private var appliedSearchText = ""
        private var appliedColorHash: Int?
        private var buildVersion = 0
        private var currentBuildTask: Task<Void, Never>?

        deinit {
            currentBuildTask?.cancel()
        }

        fileprivate func scheduleUpdate(
            logs: [LogEntry],
            searchText: String,
            backgroundColorHash: Int,
            monoFont: PlatformFont,
            defaultColor: PlatformColor,
            backgroundColor: PlatformColor,
            applyUpdate: @escaping @MainActor (NSAttributedString, Bool) -> Void
        ) {
            let filterChanged = appliedColorHash != backgroundColorHash || searchText != appliedSearchText
            let newIDs = logs.map(\.id)
            if !filterChanged, newIDs == appliedIDs {
                return
            }

            currentBuildTask?.cancel()
            buildVersion += 1
            let version = buildVersion

            currentBuildTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let built = try? await buildAttributedString(
                    logs: logs,
                    monoFont: monoFont,
                    defaultColor: defaultColor,
                    backgroundColor: backgroundColor,
                    searchText: searchText
                ) else { return }
                await MainActor.run {
                    guard let self else { return }
                    guard self.buildVersion == version else { return }
                    applyUpdate(built, filterChanged)
                    self.appliedIDs = newIDs
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
        searchText: String
    ) async throws -> NSAttributedString {
        let result = NSMutableAttributedString()
        let highlightColor: PlatformColor = .systemYellow
        let cancellationCheckInterval = 50

        for (offset, log) in logs.enumerated() {
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

            if offset > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .foregroundColor: defaultColor,
                    .font: monoFont,
                ]))
            }
            result.append(nsAttributedString)
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
        let bottomInset: CGFloat

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
            if textView.contentInset.bottom != bottomInset {
                let wasPinnedToBottom = Self.isPinnedToBottom(textView)
                textView.contentInset.bottom = bottomInset
                textView.verticalScrollIndicatorInsets.bottom = bottomInset
                if shouldAutoScroll, wasPinnedToBottom {
                    Self.scrollToBottom(textView)
                }
            }

            let backgroundColor = UIColor.systemBackground.resolvedColor(with: textView.traitCollection)
            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleUpdate(
                logs: logs,
                searchText: searchText,
                backgroundColorHash: backgroundColor.hash,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                backgroundColor: backgroundColor,
                applyUpdate: { [weak textView] text, filterChanged in
                    guard let textView else { return }
                    let wasPinnedToBottom = Self.isPinnedToBottom(textView)
                    // Assigning `attributedText` preserves `contentOffset`, so a reader
                    // scrolled up into history is not yanked around by a rebuild.
                    textView.attributedText = text
                    if shouldAutoScroll, filterChanged || wasPinnedToBottom {
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
        /// TextKit 2, which lays out only the visible viewport and keeps this O(visible)
        /// regardless of log size.
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

            // TextKit 2 lays out only the visible viewport, so replacing the document
            // stays O(visible) instead of O(log size).
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
            let shouldAutoScroll = shouldAutoScroll
            context.coordinator.scheduleUpdate(
                logs: logs,
                searchText: searchText,
                backgroundColorHash: backgroundColor.hash,
                monoFont: Self.monoFont,
                defaultColor: Self.defaultColor,
                backgroundColor: backgroundColor,
                applyUpdate: { [weak textView, weak textStorage] text, filterChanged in
                    guard let textView, let textStorage else { return }
                    let wasPinnedToBottom = Self.isPinnedToBottom(textView)
                    textStorage.setAttributedString(text)
                    if shouldAutoScroll, filterChanged || wasPinnedToBottom {
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
