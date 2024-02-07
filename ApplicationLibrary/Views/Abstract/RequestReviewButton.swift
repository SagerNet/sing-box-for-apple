#if !os(tvOS)

    import StoreKit
    import SwiftUI

    public func RequestReviewButton(label: @escaping () -> some View) -> some View {
        viewBuilder {
            if #available(iOS 16.0, macOS 13.0, visionOS 1.0, *) {
                RequestReviewButton0(label: label)
            } else {
                #if os(iOS)
                    RequestReviewButton1(label: label)
                #else
                    EmptyView()
                #endif
            }
        }
    }

    @available(iOS 16.0, macOS 13.0, visionOS 1.0, *)
    struct RequestReviewButton0<Label: View>: View {
        @Environment(\.requestReview) private var requestReview

        private let label: () -> Label
        init(label: @escaping () -> Label) {
            self.label = label
        }

        var body: some View {
            FormButton(action: {
                requestReview()
            }, label: label)
        }
    }

    struct RequestReviewButton1<Label: View>: View {
        private let label: () -> Label
        init(label: @escaping () -> Label) {
            self.label = label
        }

        var body: some View {
            Button(action: {
                SKStoreReviewController.requestReview()
            }, label: label)
        }
    }

#endif
