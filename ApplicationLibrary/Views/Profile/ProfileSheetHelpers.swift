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
    private let title: String?
    private let size: SheetSize
    private let showDoneButton: Bool
    private let onDismiss: (() -> Void)?
    private let content: () -> Content

    public init(
        title: String? = nil,
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
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                }
                content()
            }
            .toolbar {
                if showDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDismiss?()
                        }
                    }
                }
            }
        }
    #else
        private var iOSBody: some View {
            NavigationStackCompat {
                content()
                    .navigationTitle(title ?? "")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            .sheetDetent(size)
        }
    #endif
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
