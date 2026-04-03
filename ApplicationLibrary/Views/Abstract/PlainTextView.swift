#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

import SwiftUI

#if os(tvOS)
    struct PlainTextView: UIViewRepresentable {
        let content: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 24, weight: .regular)

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            // isSelectable must be true for UITextView to be focusable on tvOS.
            // Without focus, the Siri Remote cannot scroll the content.
            // SwiftUI ScrollView + Text / LazyVStack + .focusable() do NOT work
            // reliably inside navigation destinations on tvOS.
            textView.isSelectable = true
            textView.isUserInteractionEnabled = true
            textView.isScrollEnabled = true
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = .label
            textView.text = content
            textView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            return textView
        }

        func updateUIView(_: UITextView, context _: Context) {}
    }

#elseif os(iOS)
    struct PlainTextView: UIViewRepresentable {
        let content: String

        private static let monoFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            textView.textContainer.lineFragmentPadding = 0
            textView.font = Self.monoFont
            textView.textColor = .label
            textView.text = content
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return textView
        }

        func updateUIView(_: UITextView, context _: Context) {}
    }

#elseif os(macOS)
    struct PlainTextView: NSViewRepresentable {
        let content: String

        private static let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

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
            textView.textColor = .labelColor
            textView.autoresizingMask = [.width]
            textView.string = content

            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
                textContainer.lineFragmentPadding = 0
            }

            scrollView.documentView = textView
            return scrollView
        }

        func updateNSView(_: NSScrollView, context _: Context) {}
    }
#endif
