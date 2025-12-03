import Library
import SwiftUI

struct ProfileSelectorButton: View {
    let selectedItem: ProfilePreview?
    @Binding var isPickerPresented: Bool

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack {
                Text(selectedItem?.name ?? "Select Profile")
                    .font(.system(size: buttonFontSize, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: chevronSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: buttonHeight)
            .contentShape(Rectangle())
        }
        #if os(tvOS)
        .buttonStyle(SelectorButtonStyle())
        #else
        .buttonStyle(.plain)
        .selectorBackground()
        #endif
    }

    private var buttonHeight: CGFloat {
        #if os(tvOS)
            60
        #elseif os(macOS)
            32
        #else
            44
        #endif
    }

    private var buttonFontSize: CGFloat {
        #if os(macOS)
            13
        #else
            17
        #endif
    }

    private var chevronSize: CGFloat {
        #if os(macOS)
            10
        #else
            12
        #endif
    }
}

#if os(tvOS)
    private struct SelectorButtonStyle: ButtonStyle {
        @Environment(\.isFocused) private var isFocused

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? Color.white : Color.secondary.opacity(0.1))
                )
                .foregroundStyle(isFocused ? .black : .primary)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
    }
#endif

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
