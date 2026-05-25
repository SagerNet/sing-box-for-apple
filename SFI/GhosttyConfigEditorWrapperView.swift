import SwiftUI

struct GhosttyConfigEditorWrapperView: View {
    @Binding var text: String

    @StateObject private var controller = RunestoneEditorController()

    var body: some View {
        RunestoneTextView(
            text: $text,
            isEditable: true,
            language: nil,
            controller: controller
        )
    }
}
