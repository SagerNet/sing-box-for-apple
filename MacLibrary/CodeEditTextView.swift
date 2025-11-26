import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import SwiftUI

private extension NSColor {
    var forEditor: NSColor {
        usingColorSpace(.sRGB) ?? self
    }
}

private func makeTheme() -> EditorTheme {
    EditorTheme(
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

private func makeConfiguration(isEditable: Bool) -> SourceEditorConfiguration {
    SourceEditorConfiguration(
        appearance: .init(
            theme: makeTheme(),
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

    func makeNSView(context: Context) -> NSView {
        let controller = TextViewController(
            string: text,
            language: .json,
            configuration: makeConfiguration(isEditable: isEditable),
            cursorPositions: []
        )
        controller.loadView()

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

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
        context.coordinator.setupObservation()
        return containerView
    }

    func updateNSView(_: NSView, context: Context) {
        guard let controller = context.coordinator.controller else { return }
        if controller.text != text {
            controller.text = text
        }
        if controller.configuration.behavior.isEditable != isEditable {
            controller.configuration = makeConfiguration(isEditable: isEditable)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject {
        var controller: TextViewController?
        @Binding var text: String
        private var observation: NSObjectProtocol?

        init(text: Binding<String>) {
            _text = text
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
            }
        }

        deinit {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
        }
    }
}
