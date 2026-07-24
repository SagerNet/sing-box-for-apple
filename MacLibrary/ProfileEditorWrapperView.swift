import ApplicationLibrary
import Libbox
import SwiftUI

struct ProfileEditorWrapperView: View {
    @Binding var text: String
    let isEditable: Bool

    @StateObject private var controller = CodeEditEditorController()
    @State private var configurationError: String?
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            CodeEditTextView(text: $text, isEditable: isEditable, editorController: controller, enableConfigCompletion: true)

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
                applyValidationAction(ProfileValidationGate.action(for: .textChanged, popupVisible: controller.isCompletionPopupVisible))
            }
        }
        .onChangeCompat(of: controller.isCompletionPopupVisible) {
            if isEditable, !controller.isCompletionPopupVisible {
                applyValidationAction(ProfileValidationGate.action(for: .popupClosed, popupVisible: false))
            }
        }
    }

    private func applyValidationAction(_ action: ProfileValidationGate.Action) {
        switch action {
        case let .scheduleCheck(clearError):
            if clearError {
                configurationError = nil
            }
            validationTask?.cancel()
            validationTask = Task {
                try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                guard !Task.isCancelled else { return }
                applyValidationAction(ProfileValidationGate.action(for: .debounceFired, popupVisible: controller.isCompletionPopupVisible))
            }
        case .runCheck:
            Task {
                await checkConfiguration()
            }
        case .none:
            break
        }
    }

    private func checkConfiguration() async {
        let content = text
        if content.isEmpty {
            return
        }
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
        if content.isEmpty {
            return
        }
        var error: NSError?
        let result = LibboxFormatConfig(content, &error)
        if let error {
            configurationError = error.localizedDescription
            return
        }
        if let formatted = result?.value, formatted != content {
            text = formatted
        }
    }
}
