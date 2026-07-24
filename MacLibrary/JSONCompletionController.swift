import AppKit
import CodeEditTextView

@MainActor
final class JSONCompletionController: NSObject, NSTextStorageDelegate {
    private weak var textView: TextView?
    private let panel = CompletionPanelController()
    private var eventMonitor: Any?
    private var observers = [NSObjectProtocol]()
    private var activeContext: JSONCursorContext?
    private var refreshScheduled = false
    private var forcedShowPending = false
    private var suppressAutoShowOnce = false
    private var suppressAutoComma = false
    private var newlineKeystrokePending = false
    private var newlineAutoShowPending = false

    var onVisibilityChange: ((Bool) -> Void)? {
        get {
            panel.onVisibilityChange
        }
        set {
            panel.onVisibilityChange = newValue
        }
    }

    init(textView: TextView) {
        self.textView = textView
        super.init()
        ConfigSchema.preload()
        textView.addStorageDelegate(self)
        panel.onAccept = { [weak self] item in
            self?.apply(item)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            return self.handleKeyDown(event)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: TextView.textDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        })
        observers.append(center.addObserver(
            forName: TextSelectionManager.selectionChangedNotification,
            object: textView.selectionManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if self.panel.isVisible {
                    self.scheduleRefresh()
                }
            }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            Task { @MainActor in
                guard let self, let textView = self.textView else {
                    return
                }
                if window === textView.window {
                    self.hide()
                }
            }
        })
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reposition()
                }
            })
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let textView, let window = textView.window, event.window === window else {
            return event
        }
        newlineKeystrokePending = false
        let returnKey = (event.keyCode == 36 || event.keyCode == 76) && window.firstResponder === textView
        let controlSpace = event.keyCode == 49 && event.modifierFlags.contains(.control)
        if !panel.isVisible {
            if controlSpace, window.firstResponder === textView {
                refresh(auto: false)
                return nil
            }
            newlineKeystrokePending = returnKey
            return event
        }
        if controlSpace {
            hide()
            return nil
        }
        switch event.keyCode {
        case 125:
            panel.moveSelection(by: 1)
            return nil
        case 126:
            panel.moveSelection(by: -1)
            return nil
        case 36, 76, 48:
            if panel.acceptSelection() {
                return nil
            }
            hide()
            newlineKeystrokePending = returnKey
            return event
        case 53:
            hide()
            return nil
        default:
            return event
        }
    }

    private func scheduleRefresh() {
        if refreshScheduled {
            return
        }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.refreshScheduled = false
            let forced = self.forcedShowPending
            self.forcedShowPending = false
            let suppressed = self.suppressAutoShowOnce
            self.suppressAutoShowOnce = false
            let newlineTriggered = self.newlineAutoShowPending
            self.newlineAutoShowPending = false
            self.newlineKeystrokePending = false
            if suppressed, !forced {
                self.hide()
                return
            }
            self.refresh(auto: !forced, newlineTriggered: newlineTriggered)
        }
    }

    private func refresh(auto: Bool, newlineTriggered: Bool = false) {
        guard let textView, textView.isEditable, textView.window?.firstResponder === textView else {
            hide()
            return
        }
        let selection = textView.selectedRange()
        guard selection.length == 0 else {
            hide()
            return
        }
        guard let context = JSONCursorScanner.scan(text: textView.string, cursor: selection.location) else {
            hide()
            return
        }
        if auto, !context.allowsAutoShow {
            let newlineAutoShow = newlineTriggered && context.allowsNewlineAutoShow
                && CompletionInsertion.isWhitespaceOnlyLine(in: textView.string as NSString, at: selection.location)
            if !newlineAutoShow {
                hide()
                return
            }
        }
        let items = ConfigSchema.shared.completions(for: context)
        guard !items.isEmpty else {
            hide()
            return
        }
        if auto, ConfigSchema.shouldAutoDismiss(context: context, items: items) {
            hide()
            return
        }
        guard let window = textView.window, let caretRect = caretScreenRect(at: selection.location) else {
            hide()
            return
        }
        activeContext = context
        panel.show(items: items, caretRect: caretRect, parentWindow: window)
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            handleStorageEdit(editedMask: editedMask, editedRange: editedRange, delta: delta, in: textStorage)
        }
    }

    private func handleStorageEdit(editedMask: NSTextStorageEditActions, editedRange: NSRange, delta: Int, in textStorage: NSTextStorage) {
        guard editedMask.contains(.editedCharacters), !suppressAutoComma else {
            return
        }
        let string = textStorage.string as NSString
        if newlineKeystrokePending, delta > 0, editedRange.length > 0,
           editedRange.location + editedRange.length <= string.length,
           CompletionInsertion.isTypedNewlineInsertion(string.substring(with: editedRange))
        {
            newlineAutoShowPending = true
        }
        guard delta == 1, editedRange.length == 1, editedRange.location < string.length else {
            return
        }
        let character = string.character(at: editedRange.location)
        guard CompletionInsertion.isValueStartCharacter(character) else {
            return
        }
        let location = editedRange.location
        DispatchQueue.main.async { [weak self] in
            self?.insertAutoCommaIfNeeded(for: character, at: location)
        }
    }

    private func insertAutoCommaIfNeeded(for character: unichar, at location: Int) {
        guard let textView, textView.isEditable else {
            return
        }
        let text = textView.string
        let string = text as NSString
        guard location < string.length, string.character(at: location) == character else {
            return
        }
        let context = JSONCursorScanner.scan(text: text, cursor: location)
        guard let point = CompletionInsertion.typedAutoCommaPoint(typedCharacter: character, context: context, in: string, before: location) else {
            return
        }
        suppressAutoComma = true
        textView.replaceCharacters(in: NSRange(location: point, length: 0), with: ",")
        suppressAutoComma = false
    }

    private func caretScreenRect(at offset: Int) -> NSRect? {
        guard let textView, let window = textView.window else {
            return nil
        }
        guard let rect = textView.layoutManager.rectForOffset(offset) else {
            return nil
        }
        let windowRect = textView.convert(rect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func reposition() {
        guard panel.isVisible else {
            return
        }
        guard let textView, let window = textView.window else {
            hide()
            return
        }
        let selection = textView.selectedRange()
        guard let caretRect = caretScreenRect(at: selection.location) else {
            hide()
            return
        }
        panel.move(to: caretRect, parentWindow: window)
    }

    private func hide() {
        panel.hide()
        activeContext = nil
    }

    private func apply(_ item: CompletionItem) {
        guard let textView, let context = activeContext else {
            return
        }
        activeContext = nil
        let string = textView.string as NSString
        let cursor = textView.selectedRange().location
        var kind = context.kind
        if case .siblingSlot = kind {
            guard let container = context.containers.last else {
                return
            }
            if container.isObject {
                kind = .objectKey(prefix: "", replaceStart: cursor, hasOpenQuote: false)
            } else {
                kind = .value(step: .index(0), prefix: "", replaceStart: cursor, hasOpenQuote: false)
            }
        }
        switch kind {
        case let .objectKey(_, replaceStart, hasOpenQuote):
            guard replaceStart <= cursor else {
                return
            }
            var range = NSRange(location: replaceStart, length: cursor - replaceStart)
            var afterIndex = cursor
            if hasOpenQuote, cursor < string.length, string.character(at: cursor) == unichar(UInt8(ascii: "\"")) {
                range.length += 1
                afterIndex = cursor + 1
            }
            var colonFollows = false
            var index = afterIndex
            while index < string.length {
                let character = string.character(at: index)
                if character == unichar(UInt8(ascii: " ")) || character == unichar(UInt8(ascii: "\t")) {
                    index += 1
                    continue
                }
                colonFollows = character == unichar(UInt8(ascii: ":"))
                break
            }
            let plan = CompletionInsertion.keyInsertion(
                name: item.insertText,
                shape: item.valueShape,
                colonFollows: colonFollows,
                siblingFollows: CompletionInsertion.siblingFollows(in: string, from: range.location + range.length, containerIsObject: true),
                indent: CompletionInsertion.lineIndent(in: string, at: range.location)
            )
            perform(plan, replacing: range, in: string, expandingFrom: context.containers.last?.openOffset)
        case let .value(_, _, replaceStart, hasOpenQuote):
            guard replaceStart <= cursor else {
                return
            }
            var range = NSRange(location: replaceStart, length: cursor - replaceStart)
            if hasOpenQuote, cursor < string.length, string.character(at: cursor) == unichar(UInt8(ascii: "\"")) {
                range.length += 1
            }
            let sibling = CompletionInsertion.siblingFollows(
                in: string,
                from: range.location + range.length,
                containerIsObject: context.containers.last?.isObject ?? true
            )
            let plan: CompletionInsertionPlan
            var expandOffset: Int?
            if let elements = item.arrayExample {
                plan = CompletionInsertion.arrayExampleInsertion(
                    elements: elements,
                    siblingFollows: sibling,
                    indent: CompletionInsertion.lineIndent(in: string, at: range.location)
                )
            } else if let shape = item.valueShape,
                      let formPlan = CompletionInsertion.formInsertion(
                          shape: shape,
                          siblingFollows: sibling,
                          indent: CompletionInsertion.lineIndent(in: string, at: range.location)
                      )
            {
                plan = formPlan
                if shape == .object || shape == .array {
                    expandOffset = context.containers.last?.openOffset
                }
            } else {
                plan = CompletionInsertion.valueInsertion(text: item.insertText, quoted: item.isString, siblingFollows: sibling)
            }
            perform(plan, replacing: range, in: string, expandingFrom: expandOffset)
        case .siblingSlot:
            break
        }
    }

    private func perform(_ plan: CompletionInsertionPlan, replacing range: NSRange, in string: NSString, expandingFrom openOffset: Int? = nil) {
        guard let textView else {
            return
        }
        let resolved = CompletionInsertion.resolve(plan: plan, replacing: range, in: string, expandingFrom: openOffset)
        hide()
        suppressAutoComma = true
        textView.replaceCharacters(in: resolved.range, with: resolved.text)
        suppressAutoComma = false
        textView.selectionManager.setSelectedRange(NSRange(location: resolved.cursorLocation, length: 0))
        if plan.retrigger != .none {
            forcedShowPending = true
            scheduleRefresh()
        } else {
            suppressAutoShowOnce = true
        }
    }
}
