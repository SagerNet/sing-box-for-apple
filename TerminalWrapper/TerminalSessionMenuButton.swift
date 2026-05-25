#if os(iOS)
    import SwiftUI
    import UIKit

    @available(iOS 17.0, *)
    struct TerminalSessionMenuButton: UIViewRepresentable {
        @ObservedObject var sessionManager: TerminalSessionManager
        @Environment(\.colorScheme) private var colorScheme

        func makeUIView(context _: Context) -> UIButton {
            let button = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(scale: .large)
            button.setImage(UIImage(systemName: "line.3.horizontal.circle", withConfiguration: config), for: .normal)
            if #available(iOS 26.0, *) {
                button.tintColor = colorScheme == .dark ? .white : .black
            }
            button.showsMenuAsPrimaryAction = true
            button.menu = createMenu()
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }

        func updateUIView(_ uiView: UIButton, context _: Context) {
            uiView.menu = createMenu()
            if #available(iOS 26.0, *) {
                uiView.tintColor = colorScheme == .dark ? .white : .black
            }
        }

        private func createMenu() -> UIMenu {
            let newSessionAction = UIAction(
                title: NSLocalizedString("New Session", comment: ""),
                image: UIImage(systemName: "plus")
            ) { _ in
                sessionManager.createDuplicateSession()
            }

            let newSessionMenu = UIMenu(title: "", options: .displayInline, children: [newSessionAction])

            let sessionActions: [UIMenuElement] = sessionManager.sessions.map { managed in
                let isActive = managed.id == sessionManager.activeSessionID
                let title = sessionManager.displayName(for: managed)

                return UIAction(
                    title: title,
                    state: isActive ? .on : .off
                ) { _ in
                    sessionManager.switchTo(id: managed.id)
                }
            }

            let sessionsMenu = UIMenu(title: "", options: .displayInline, children: sessionActions)

            return UIMenu(children: [newSessionMenu, sessionsMenu])
        }
    }
#endif
