import Library
import SwiftUI

#if os(iOS)
    import UIKit

    class ShareViewController: UIViewController {
        private let viewModel = ShareViewModel()

        override func viewDidLoad() {
            super.viewDidLoad()
            ShareViewModel.setupService()
            bind()
            let hosting = UIHostingController(rootView: ShareView(viewModel: viewModel))
            addChild(hosting)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
            viewModel.load(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        }

        private func bind() {
            viewModel.onFinish = { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            viewModel.onCancel = { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
            viewModel.onOpenApplication = { [weak self] url in
                self?.extensionContext?.open(url)
            }
        }
    }

#elseif os(macOS)
    import AppKit

    class ShareViewController: NSViewController {
        private let viewModel = ShareViewModel()

        override func loadView() {
            ShareViewModel.setupService()
            bind()
            let hosting = NSHostingController(rootView: ShareView(viewModel: viewModel))
            hosting.preferredContentSize = NSSize(width: 420, height: 480)
            addChild(hosting)
            view = hosting.view
            preferredContentSize = hosting.preferredContentSize
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            viewModel.load(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        }

        private func bind() {
            viewModel.onFinish = { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            viewModel.onCancel = { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
            viewModel.onOpenApplication = { url in
                NSWorkspace.shared.open(url)
            }
        }
    }
#endif
