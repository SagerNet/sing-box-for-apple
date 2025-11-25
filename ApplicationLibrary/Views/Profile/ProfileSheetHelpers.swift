import Library
import SwiftUI

public enum SheetSize {
    case large
    case medium

    #if os(iOS) || os(tvOS)
        @available(iOS 16.0, tvOS 17.0, *)
        var presentationDetent: SwiftUI.PresentationDetent {
            switch self {
            case .large: return .large
            case .medium: return .medium
            }
        }
    #endif
}

@MainActor
public struct NavigationSheet<Content: View>: View {
    private let title: String
    private let size: SheetSize
    private let showDoneButton: Bool
    private let onDismiss: (() -> Void)?
    private let content: () -> Content

    public init(
        title: String,
        size: SheetSize = .large,
        showDoneButton: Bool = false,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.size = size
        self.showDoneButton = showDoneButton
        self.onDismiss = onDismiss
        self.content = content
    }

    public var body: some View {
        NavigationStackCompat {
            content()
                .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .toolbar {
                if showDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDismiss?()
                        }
                    }
                }
            }
            #endif
        }
        #if os(iOS) || os(tvOS)
        .sheetDetent(size)
        #endif
    }
}

#if os(iOS) || os(tvOS)
    private extension View {
        @ViewBuilder
        func sheetDetent(_ size: SheetSize) -> some View {
            if #available(iOS 16.0, tvOS 17.0, *) {
                self.presentationDetents([size.presentationDetent])
                    .presentationDragIndicator(.visible)
            } else {
                self
            }
        }
    }
#endif
