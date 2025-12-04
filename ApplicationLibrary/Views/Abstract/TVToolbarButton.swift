#if os(tvOS)
    import SwiftUI
    import UIKit

    /// Workaround for tvOS SwiftUI bug where toolbar Button text labels fail to render properly.
    /// Using UIButton via UIViewRepresentable bypasses this issue.
    struct TVToolbarButton: UIViewRepresentable {
        let title: String
        let action: () -> Void

        func makeUIView(context: Context) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .primaryActionTriggered)
            return button
        }

        func updateUIView(_ uiView: UIButton, context: Context) {
            uiView.setTitle(title, for: .normal)
            uiView.invalidateIntrinsicContentSize()
            uiView.sizeToFit()
            context.coordinator.action = action
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(action: action)
        }

        class Coordinator: NSObject {
            var action: () -> Void
            init(action: @escaping () -> Void) {
                self.action = action
            }

            @objc func buttonTapped() {
                action()
            }
        }
    }
#endif
