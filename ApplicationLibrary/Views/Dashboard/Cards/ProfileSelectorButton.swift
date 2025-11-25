import Library
import SwiftUI
#if os(iOS) || os(tvOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// A custom view that looks like a navigation link but opens a dropdown menu
struct ProfileSelectorButton: View {
    let items: [ProfilePreview]
    let selectedItem: ProfilePreview?
    let onSelect: (Int64) -> Void

    init(
        items: [ProfilePreview],
        selectedItem: ProfilePreview?,
        onSelect: @escaping (Int64) -> Void
    ) {
        self.items = items
        self.selectedItem = selectedItem
        self.onSelect = onSelect
    }

    var body: some View {
        #if os(iOS) || os(tvOS)
            ProfileSelectorUIButton(
                items: items,
                selectedItem: selectedItem,
                onSelect: onSelect
            )
            .frame(height: 44)
            .selectorBackground()
        #elseif os(macOS)
            ProfileSelectorNSButton(
                items: items,
                selectedItem: selectedItem,
                onSelect: onSelect
            )
            .frame(height: 32)
            .selectorBackground()
        #endif
    }
}

// MARK: - UIKit Implementation (iOS/tvOS)

#if os(iOS) || os(tvOS)
    /// Custom UIButton subclass that allows customizing menu attachment point
    private class MenuAttachmentButton: UIButton {
        override func menuAttachmentPoint(for _: UIContextMenuConfiguration) -> CGPoint {
            // Attach menu to bottom-leading corner of the button
            CGPoint(x: 0, y: bounds.height)
        }
    }

    /// UIViewRepresentable wrapper for UIButton with UIMenu
    private struct ProfileSelectorUIButton: UIViewRepresentable {
        let items: [ProfilePreview]
        let selectedItem: ProfilePreview?
        let onSelect: (Int64) -> Void

        func makeUIView(context _: Context) -> MenuAttachmentButton {
            let button = MenuAttachmentButton(type: .system)
            button.showsMenuAsPrimaryAction = true
            button.contentHorizontalAlignment = .fill

            // Configure button appearance
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            button.configuration = config

            updateButtonContent(button)
            updateMenu(button)

            return button
        }

        func updateUIView(_ button: MenuAttachmentButton, context _: Context) {
            updateButtonContent(button)
            updateMenu(button)
        }

        private func updateButtonContent(_ button: MenuAttachmentButton) {
            // Remove existing subviews
            for subview in button.subviews {
                if subview is UIStackView {
                    subview.removeFromSuperview()
                }
            }

            // Create content stack
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.distribution = .fill
            stackView.spacing = 8
            stackView.isUserInteractionEnabled = false
            stackView.translatesAutoresizingMaskIntoConstraints = false

            // Title label
            let titleLabel = UILabel()
            titleLabel.text = selectedItem?.name ?? "Select Profile"
            titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
            titleLabel.textColor = .label
            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            // Chevron image
            let chevronConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let chevronImage = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: chevronConfig)
            let chevronView = UIImageView(image: chevronImage)
            chevronView.tintColor = .secondaryLabel
            chevronView.setContentHuggingPriority(.required, for: .horizontal)

            stackView.addArrangedSubview(titleLabel)
            stackView.addArrangedSubview(chevronView)

            button.addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
                stackView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
                stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }

        private func updateMenu(_ button: MenuAttachmentButton) {
            let actions = items.map { item in
                UIAction(
                    title: item.name,
                    image: UIImage(systemName: item.type.iconName)
                ) { [item] _ in
                    onSelect(item.id)
                }
            }

            button.menu = UIMenu(children: actions)
        }
    }
#endif

// MARK: - AppKit Implementation (macOS)

#if os(macOS)
    /// NSViewRepresentable wrapper for a clickable view with NSMenu
    private struct ProfileSelectorNSButton: NSViewRepresentable {
        let items: [ProfilePreview]
        let selectedItem: ProfilePreview?
        let onSelect: (Int64) -> Void

        func makeNSView(context: Context) -> NSView {
            let containerView = MenuContainerView()
            containerView.coordinator = context.coordinator
            updateContent(containerView)
            context.coordinator.updateMenu(items: items, onSelect: onSelect)
            return containerView
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let containerView = nsView as? MenuContainerView else { return }
            updateContent(containerView)
            context.coordinator.updateMenu(items: items, onSelect: onSelect)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        private func updateContent(_ containerView: MenuContainerView) {
            containerView.titleText = selectedItem?.name ?? "Select Profile"
        }

        private class MenuContainerView: NSView {
            weak var coordinator: Coordinator?
            private let titleLabel = NSTextField(labelWithString: "")
            private let chevronView = NSImageView()

            var titleText: String = "" {
                didSet {
                    titleLabel.stringValue = titleText
                }
            }

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                setupViews()
            }

            required init?(coder: NSCoder) {
                super.init(coder: coder)
                setupViews()
            }

            private func setupViews() {
                titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
                titleLabel.textColor = .labelColor
                titleLabel.alignment = .left
                titleLabel.translatesAutoresizingMaskIntoConstraints = false
                addSubview(titleLabel)

                let chevronConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                chevronView.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(chevronConfig)
                chevronView.contentTintColor = .secondaryLabelColor
                chevronView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(chevronView)

                NSLayoutConstraint.activate([
                    titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                    titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                    chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                    chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
                ])
            }

            override func mouseDown(with _: NSEvent) {
                coordinator?.showMenu(in: self)
            }

            override func resetCursorRects() {
                addCursorRect(bounds, cursor: .pointingHand)
            }
        }

        class Coordinator: NSObject {
            private var menu = NSMenu()
            private var onSelectCallback: ((Int64) -> Void)?

            func updateMenu(items: [ProfilePreview], onSelect: @escaping (Int64) -> Void) {
                menu.removeAllItems()
                onSelectCallback = onSelect

                for item in items {
                    let menuItem = NSMenuItem(
                        title: item.name,
                        action: #selector(menuItemSelected(_:)),
                        keyEquivalent: ""
                    )
                    menuItem.target = self
                    menuItem.tag = Int(item.id)
                    menuItem.image = NSImage(systemSymbolName: item.type.iconName, accessibilityDescription: nil)
                    menu.addItem(menuItem)
                }
            }

            @objc private func menuItemSelected(_ sender: NSMenuItem) {
                onSelectCallback?(Int64(sender.tag))
            }

            func showMenu(in view: NSView) {
                let location = NSPoint(x: 0, y: view.bounds.height + 4)
                menu.popUp(positioning: nil, at: location, in: view)
            }
        }
    }
#endif

// MARK: - ProfileType Extension

private extension ProfileType {
    var iconName: String {
        switch self {
        case .local:
            "doc.fill"
        case .icloud:
            "icloud.fill"
        case .remote:
            "cloud.fill"
        }
    }
}

// MARK: - View Extension

private extension View {
    @ViewBuilder
    func selectorBackground() -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        } else {
            background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
    }
}
