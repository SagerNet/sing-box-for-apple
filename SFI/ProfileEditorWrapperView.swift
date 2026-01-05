import ApplicationLibrary
import Libbox
import SwiftUI

struct ProfileEditorWrapperView: View {
    @Binding var text: String
    let isEditable: Bool

    @StateObject private var controller = RunestoneEditorController()
    @State private var configurationError: String?
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            RunestoneTextView(text: $text, isEditable: isEditable, controller: controller)

            if isEditable {
                EditorToolbarView(
                    canUndo: controller.canUndo,
                    canRedo: controller.canRedo,
                    onUndo: { controller.undo() },
                    onRedo: { controller.redo() },
                    onFormat: { formatConfiguration() },
                    onInsertSymbol: { controller.insertSymbol($0) },
                    configurationError: configurationError,
                    onDismissError: { configurationError = nil }
                )
            }
        }
        .onChangeCompat(of: text) {
            if isEditable {
                scheduleValidation()
            }
        }
    }

    private func scheduleValidation() {
        configurationError = nil
        validationTask?.cancel()
        validationTask = Task {
            try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
            guard !Task.isCancelled else { return }
            await checkConfiguration()
        }
    }

    private func checkConfiguration() async {
        let content = text
        if content.isEmpty { return }
        var error: NSError?
        LibboxCheckConfig(content, &error)
        if let error {
            configurationError = error.localizedDescription
        } else {
            configurationError = nil
        }
    }

    private func formatConfiguration() {
        let content = text
        if content.isEmpty { return }
        var error: NSError?
        let result = LibboxFormatConfig(content, &error)
        if let error {
            configurationError = error.localizedDescription
            return
        }
        if let formatted = result?.value, formatted != content {
            controller.setText(formatted)
        }
    }
}
