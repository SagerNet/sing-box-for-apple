#if os(iOS)
    import Runestone
    import SwiftUI
    import TreeSitterJSON5Runestone

    struct RunestoneTextView: UIViewRepresentable {
        @Binding var text: String
        let isEditable: Bool

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

            return textView
        }

        func updateUIView(_ textView: TextView, context _: Context) {
            if textView.text != text {
                textView.text = text
            }
            if textView.isEditable != isEditable {
                textView.isEditable = isEditable
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: TextViewDelegate {
            var parent: RunestoneTextView

            init(_ parent: RunestoneTextView) {
                self.parent = parent
            }

            func textViewDidChange(_ textView: TextView) {
                parent.text = textView.text
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
#endif
