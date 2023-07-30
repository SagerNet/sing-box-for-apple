import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

public struct ShareButton<Label>: View where Label: View {
    private let items: () throws -> [Any]
    private let label: Label
    @Binding private var alert: Alert?

    public init(_ alert: Binding<Alert?>, @ViewBuilder label: () -> Label, items: @escaping () throws -> [Any]) {
        _alert = alert
        self.items = items
        self.label = label()
    }

    #if canImport(AppKit)
        @State private var sharePresented = false
    #endif

    public var body: some View {
        Button {
            #if os(iOS)
                do {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        try windowScene.keyWindow?.rootViewController?.present(UIActivityViewController(activityItems: items(), applicationActivities: nil), animated: true, completion: nil)
                    }
                } catch {
                    alert = Alert(error)
                }
            #elseif canImport(AppKit)
                sharePresented = true
            #endif
        } label: {
            label
        }
        #if canImport(AppKit)
        .background(SharingServicePicker($sharePresented, $alert, items))
        #endif
    }

    private func shareItems() {}
}

#if canImport(AppKit)
    private struct SharingServicePicker: NSViewRepresentable {
        @Binding private var isPresented: Bool
        @Binding private var alert: Alert?
        private let items: () throws -> [Any]

        init(_ isPresented: Binding<Bool>, _ alert: Binding<Alert?>, _ items: @escaping () throws -> [Any]) {
            _isPresented = isPresented
            _alert = alert
            self.items = items
        }

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            if isPresented {
                do {
                    let picker = try NSSharingServicePicker(items: items())
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
