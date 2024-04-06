import Foundation
import Library
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
public struct ProfileShareButton<Label>: View where Label: View {
    private let alert: Binding<Alert?>
    private let profile: Profile
    private let label: () -> Label

    public init(_ alert: Binding<Alert?>, _ profile: Profile, label: @escaping () -> Label) {
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
            try profile.toContent().generateShareFile()
        }
    }
}

public struct ShareButtonCompat<Label>: View where Label: View {
    private let label: () -> Label
    private let itemURL: () throws -> URL

    @Binding private var alert: Alert?

    #if os(macOS)
        @State private var sharePresented = false
    #endif

    public init(_ alert: Binding<Alert?>, @ViewBuilder label: @escaping () -> Label, itemURL: @escaping () throws -> URL) {
        _alert = alert
        self.label = label
        self.itemURL = itemURL
    }

    public var body: some View {
        Button(action: shareItem, label: label)
        #if os(macOS)
            .background(SharingServicePicker($sharePresented, $alert, itemURL))
        #endif
    }

    private func shareItem() {
        #if os(iOS)
            Task {
                await shareItem0()
            }
        #elseif os(macOS)
            sharePresented = true
        #endif
    }

    #if os(iOS)
        private nonisolated func shareItem0() async {
            do {
                let shareItem = try itemURL()
                await MainActor.run {
                    shareItem1(shareItem)
                }
            } catch {
                await MainActor.run {
                    alert = Alert(error)
                }
            }
        }

        private func shareItem1(_ item: URL) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.keyWindow?.rootViewController?.present(UIActivityViewController(activityItems: [item], applicationActivities: nil), animated: true, completion: nil)
            }
        }
    #endif
}

#if os(macOS)
    private struct SharingServicePicker: NSViewRepresentable {
        @Binding private var isPresented: Bool
        @Binding private var alert: Alert?
        private let item: () throws -> URL

        init(_ isPresented: Binding<Bool>, _ alert: Binding<Alert?>, _ item: @escaping () throws -> URL) {
            _isPresented = isPresented
            _alert = alert
            self.item = item
        }

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isPresented {
                do {
                    let picker = try NSSharingServicePicker(items: [item()])
                    picker.delegate = context.coordinator
                    DispatchQueue.main.async {
                        picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
                    }
                } catch {
                    alert = Alert(error)
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
