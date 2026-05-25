import CodeEditLanguages
import SwiftUI

struct GhosttyConfigEditorWrapperView: View {
    @Binding var text: String

    var body: some View {
        CodeEditTextView(
            text: $text,
            isEditable: true,
            language: .toml
        )
    }
}
