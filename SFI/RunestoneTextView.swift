import Runestone
import SwiftUI
import TreeSitterJSON5Runestone

@MainActor
public final class RunestoneEditorController: ObservableObject {
    weak var textView: TextView?

    @Published public var canUndo = false
    @Published public var canRedo = false

    public init() {}

    public func undo() {
        textView?.undoManager?.undo()
        updateUndoState()
    }

    public func redo() {
        textView?.undoManager?.redo()
        updateUndoState()
    }

    public func insertSymbol(_ symbol: String) {
        guard let textView else { return }
        textView.insertText(symbol)
    }

    public func setText(_ newText: String) {
        guard let textView else { return }
        if let textRange = textView.textRange(from: textView.beginningOfDocument, to: textView.endOfDocument) {
            textView.selectedTextRange = textRange
            textView.insertText(newText)
        }
    }

    func updateUndoState() {
        canUndo = textView?.undoManager?.canUndo ?? false
        canRedo = textView?.undoManager?.canRedo ?? false
    }
}

struct RunestoneTextView: UIViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let controller: RunestoneEditorController?

    init(text: Binding<String>, isEditable: Bool, controller: RunestoneEditorController? = nil) {
        _text = text
        self.isEditable = isEditable
        self.controller = controller
    }

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()

        textView.showLineNumbers = true
        textView.isLineWrappingEnabled = false
        textView.showTabs = false
        textView.showSpaces = false
        textView.showLineBreaks = false
        textView.showSoftLineBreaks = false
        textView.showNonBreakingSpaces = false

        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no

        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.contentInsetAdjustmentBehavior = .always
        textView.alwaysBounceVertical = true

        textView.kern = 0.3
        textView.lineHeightMultiplier = 1.3

        textView.characterPairs = [
            BasicCharacterPair(leading: "{", trailing: "}"),
            BasicCharacterPair(leading: "[", trailing: "]"),
            BasicCharacterPair(leading: "\"", trailing: "\""),
        ]

        let theme = ProfileEditorTheme()
        let state = TextViewState(text: text, theme: theme, language: .json5)
        textView.setState(state)

        textView.isEditable = isEditable
        textView.editorDelegate = context.coordinator

        context.coordinator.textView = textView
        controller?.textView = textView
        Task { @MainActor in
            controller?.updateUndoState()
        }

        return textView
    }

    func updateUIView(_ textView: TextView, context _: Context) {
        if textView.text != text {
            textView.text = text
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        controller?.textView = textView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: TextViewDelegate {
        var parent: RunestoneTextView
        weak var textView: TextView?

        init(_ parent: RunestoneTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: TextView) {
            parent.text = textView.text
            Task { @MainActor in
                parent.controller?.updateUndoState()
            }
        }
    }
}

final class BasicCharacterPair: CharacterPair {
    let leading: String
    let trailing: String

    init(leading: String, trailing: String) {
        self.leading = leading
        self.trailing = trailing
    }
}
