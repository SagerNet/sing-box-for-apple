import Foundation
import Library
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
public struct ProfileShareButton<Label: View>: View {
    private let alert: Binding<AlertState?>
    private let profile: Profile
    private let label: () -> Label

    public init(_ alert: Binding<AlertState?>, _ profile: Profile, label: @escaping () -> Label) {
        self.alert = alert
        self.profile = profile
        self.label = label
    }

    public var body: some View {
        #if os(iOS)
            if #available(iOS 17.4, *) {
                bodyCompat
            } else if #available(iOS 16.0, *) {
                ShareLink(item: profile, subject: Text(profile.name), preview: SharePreview("Share profile"), label: label)
            } else if UIDevice.current.userInterfaceIdiom != .pad {
                bodyCompat
            }
        #else
            bodyCompat
        #endif
    }

    private var bodyCompat: some View {
        ShareButtonCompat(alert, label: label) {
            try await profile.generateShareFileAsync()
        }
    }
}

public struct ShareButtonCompat<Label: View>: View {
    private let label: () -> Label
    private let itemURL: () async throws -> URL

    @Binding private var alert: AlertState?

    #if os(macOS)
        @State private var sharePresented = false
        @State private var shareItemURL: URL?
    #endif

    public init(_ alert: Binding<AlertState?>, @ViewBuilder label: @escaping () -> Label, itemURL: @escaping () async throws -> URL) {
        _alert = alert
        self.label = label
        self.itemURL = itemURL
    }

    public var body: some View {
        Button(action: shareItem, label: label)
            .buttonStyle(.plain)
        #if os(macOS)
            .background(SharingServicePicker($sharePresented, $alert, $shareItemURL))
        #endif
    }

    private func shareItem() {
        #if os(iOS)
            Task {
                await shareItemAsync()
            }
        #elseif os(macOS)
            Task {
                await shareItemAsync()
            }
        #endif
    }

    #if os(iOS)
        private nonisolated func shareItemAsync() async {
            do {
                let shareItem = try await itemURL()
                await MainActor.run {
                    presentShareController(shareItem)
                }
            } catch {
                await MainActor.run {
                    alert = AlertState(action: "prepare share file", error: error)
                }
            }
        }

        private func presentShareController(_ item: URL) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.keyWindow?.rootViewController
            else {
                return
            }
            var topViewController = rootViewController
            while let presented = topViewController.presentedViewController {
                topViewController = presented
            }
            topViewController.present(
                UIActivityViewController(activityItems: [item], applicationActivities: nil),
                animated: true
            )
        }

    #elseif os(macOS)
        private nonisolated func shareItemAsync() async {
            do {
                let shareItem = try await itemURL()
                await MainActor.run {
                    shareItemURL = shareItem
                    sharePresented = true
                }
            } catch {
                await MainActor.run {
                    alert = AlertState(action: "prepare share file", error: error)
                }
            }
        }
    #endif
}

#if os(macOS)
    private struct SharingServicePicker: NSViewRepresentable {
        @Binding private var isPresented: Bool
        @Binding private var alert: AlertState?
        @Binding private var item: URL?

        init(_ isPresented: Binding<Bool>, _ alert: Binding<AlertState?>, _ item: Binding<URL?>) {
            _isPresented = isPresented
            _alert = alert
            _item = item
        }

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isPresented {
                guard let item else {
                    return
                }
                let picker = NSSharingServicePicker(items: [item])
                picker.delegate = context.coordinator
                picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                DispatchQueue.main.async {
                    isPresented = false
                    self.item = nil
                }
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, NSSharingServicePickerDelegate {
            private let parent: SharingServicePicker

            init(_ parent: SharingServicePicker) {
                self.parent = parent
            }

            func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose _: NSSharingService?) {
                sharingServicePicker.delegate = nil
                parent.isPresented = false
            }
        }
    }

#endif
