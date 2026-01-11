import SwiftUI

#if os(iOS)
    import UIKit

    public extension View {
        @ViewBuilder
        func tabViewBottomAccessoryCompat(
            isEnabled: Bool = true,
            useSystemAccessory: Bool = true,
            @ViewBuilder content: @escaping () -> some View
        ) -> some View {
            if isEnabled {
                if #available(iOS 26.0, *), useSystemAccessory {
                    tabViewBottomAccessory {
                        content()
                    }
                } else {
                    safeAreaInset(edge: .bottom, spacing: 0) {
                        TabViewBottomAccessoryContainer(content: content)
                    }
                }
            } else {
                self
            }
        }
    }

    private struct TabViewBottomAccessoryContainer<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: TabViewBottomAccessoryMetrics.height)
                .background(
                    .bar,
                    in: RoundedRectangle(
                        cornerRadius: TabViewBottomAccessoryMetrics.cornerRadius,
                        style: .continuous
                    )
                )
                .padding(.horizontal, TabViewBottomAccessoryMetrics.horizontalPadding)
                .padding(.top, TabViewBottomAccessoryMetrics.topPadding)
                .padding(.bottom, TabViewBottomAccessoryMetrics.bottomPadding)
        }
    }

    private enum TabViewBottomAccessoryMetrics {
        static var height: CGFloat {
            let toolbar = UIToolbar()
            let size = toolbar.sizeThatFits(CGSize(width: UIScreen.main.bounds.width, height: 0))
            return size.height > 0 ? size.height : 44
        }

        static var cornerRadius: CGFloat {
            height * 0.5
        }

        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 12
    }
#endif
