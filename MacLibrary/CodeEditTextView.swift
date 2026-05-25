import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

@MainActor
public final class CodeEditEditorController: ObservableObject {
    weak var controller: TextViewController?

    @Published public var canUndo = false
    @Published public var canRedo = false

    public init() {}

    public func undo() {
        controller?.textView.undoManager?.undo()
        updateUndoState()
    }

    public func redo() {
        controller?.textView.undoManager?.redo()
        updateUndoState()
    }

    public func insertSymbol(_ symbol: String) {
        guard let textView = controller?.textView else { return }
        textView.insertText(symbol, replacementRange: textView.selectedRange())
    }

    func updateUndoState() {
        canUndo = controller?.textView.undoManager?.canUndo ?? false
        canRedo = controller?.textView.undoManager?.canRedo ?? false
    }
}

private func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

private final class CodeEditContainerView: NSView {
    var onAppearanceChange: ((Bool) -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?(isDark(effectiveAppearance))
    }
}

private extension NSColor {
    var forEditor: NSColor {
        usingColorSpace(.deviceRGB) ?? self
    }
}

private func makeTheme(isDark: Bool) -> EditorTheme {
    var theme: EditorTheme!
    let build = {
        theme = EditorTheme(
            text: .init(color: NSColor.labelColor.forEditor),
            insertionPoint: NSColor.labelColor.forEditor,
            invisibles: .init(color: NSColor.tertiaryLabelColor.forEditor),
            background: NSColor.textBackgroundColor.forEditor,
            lineHighlight: NSColor.quaternaryLabelColor.forEditor,
            selection: NSColor.selectedTextBackgroundColor.forEditor,
            keywords: .init(color: NSColor.systemPurple.forEditor),
            commands: .init(color: NSColor.systemCyan.forEditor),
            types: .init(color: NSColor.systemCyan.forEditor),
            attributes: .init(color: NSColor.systemCyan.forEditor),
            variables: .init(color: NSColor.labelColor.forEditor),
            values: .init(color: NSColor.systemOrange.forEditor),
            numbers: .init(color: NSColor.systemOrange.forEditor),
            strings: .init(color: NSColor.systemGreen.forEditor),
            characters: .init(color: NSColor.systemGreen.forEditor),
            comments: .init(color: NSColor.secondaryLabelColor.forEditor)
        )
    }
    if let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) {
        appearance.performAsCurrentDrawingAppearance(build)
    } else {
        build()
    }
    return theme
}

private func makeConfiguration(isEditable: Bool, isDark: Bool) -> SourceEditorConfiguration {
    SourceEditorConfiguration(
        appearance: .init(
            theme: makeTheme(isDark: isDark),
            font: .monospacedSystemFont(ofSize: 14, weight: .regular),
            lineHeightMultiple: 1.3,
            wrapLines: false
        ),
        behavior: .init(
            isEditable: isEditable,
            isSelectable: true
        ),
        peripherals: .init(
            showMinimap: false,
            showFoldingRibbon: false
        )
    )
}

struct CodeEditTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let language: CodeLanguage
    let editorController: CodeEditEditorController?

    init(
        text: Binding<String>,
        isEditable: Bool,
        language: CodeLanguage = .json,
        editorController: CodeEditEditorController? = nil
    ) {
        _text = text
        self.isEditable = isEditable
        self.language = language
        self.editorController = editorController
    }

    func makeNSView(context: Context) -> NSView {
        let containerView = CodeEditContainerView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        let initialIsDark = isDark(containerView.effectiveAppearance)

        let controller = TextViewController(
            string: text,
            language: language,
            configuration: makeConfiguration(isEditable: isEditable, isDark: initialIsDark),
            cursorPositions: []
        )
        controller.loadView()

        let controllerView = controller.view
        controllerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(controllerView)

        NSLayoutConstraint.activate([
            controllerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            controllerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            controllerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controllerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        context.coordinator.controller = controller
        context.coordinator.lastIsDark = initialIsDark
        context.coordinator.setupObservation()
        containerView.onAppearanceChange = { [weak coordinator = context.coordinator] dark in
            guard let coordinator, let controller = coordinator.controller else { return }
            guard coordinator.lastIsDark != dark else { return }
            coordinator.lastIsDark = dark
            controller.configuration.appearance.theme = makeTheme(isDark: dark)
        }
        editorController?.controller = controller
        Task { @MainActor in
            editorController?.updateUndoState()
        }

        return containerView
    }

    func updateNSView(_: NSView, context: Context) {
        guard let controller = context.coordinator.controller else { return }
        if controller.text != text {
            controller.text = text
            // setText() creates a new Highlighter but doesn't trigger initial highlighting.
            // Re-setting the language forces the highlighter to invalidate and re-highlight.
            controller.language = language
        }
        if controller.configuration.behavior.isEditable != isEditable {
            controller.configuration.behavior.isEditable = isEditable
        }
        editorController?.controller = controller
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, editorController: editorController)
    }

    class Coordinator: NSObject {
        var controller: TextViewController?
        var lastIsDark: Bool?
        @Binding var text: String
        private var observation: NSObjectProtocol?
        private weak var editorController: CodeEditEditorController?

        init(text: Binding<String>, editorController: CodeEditEditorController?) {
            _text = text
            self.editorController = editorController
            super.init()
        }

        func setupObservation() {
            guard let controller else { return }
            observation = NotificationCenter.default.addObserver(
                forName: TextView.textDidChangeNotification,
                object: controller.textView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let controller = self.controller else { return }
                self.text = controller.text
                Task { @MainActor in
                    self.editorController?.updateUndoState()
                }
            }
        }

        deinit {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
        }
    }
}
