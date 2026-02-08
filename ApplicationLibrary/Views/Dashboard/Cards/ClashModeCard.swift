import Libbox
import Library
import SwiftUI

public struct ClashModeCard: View {
    @EnvironmentObject private var commandClient: CommandClient
    @State private var clashMode: String = ""
    @State private var alert: AlertState?
    #if !os(tvOS)
        @Namespace private var tabNamespace
        @State private var availableWidth: CGFloat = 0
        @State private var tabBarWidth: CGFloat = 0
    #endif

    public init() {}

    public var body: some View {
        if shouldShowPicker {
            DashboardCardView(title: "", isHalfWidth: false) {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardCardHeader(icon: "circle.grid.2x2.fill", title: "Mode")
                    #if os(tvOS)
                        modeMenu
                    #else
                        if tabsFit {
                            modeTabBar
                        } else {
                            modeMenu
                        }
                    #endif
                }
                #if !os(tvOS)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: AvailableWidthKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(AvailableWidthKey.self) { newValue in
                    availableWidth = newValue
                }
                .background(
                    tabBarContent
                        .fixedSize()
                        .hidden()
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: TabBarWidthKey.self, value: geo.size.width)
                        })
                )
                .onPreferenceChange(TabBarWidthKey.self) { newValue in
                    tabBarWidth = newValue
                }
                #endif
            }
            .onAppear {
                clashMode = commandClient.clashMode
            }
            .onChangeCompat(of: commandClient.clashMode) { newValue in
                clashMode = newValue
            }
            .alert($alert)
        }
    }

    private var modeMenu: some View {
        Menu {
            ForEach(commandClient.clashModeList, id: \.self) { mode in
                Button {
                    clashMode = mode
                    Task {
                        await setClashMode(mode)
                    }
                } label: {
                    if mode == clashMode {
                        Label(mode, systemImage: "checkmark")
                    } else {
                        Text(mode)
                    }
                }
            }
        } label: {
            HStack {
                Text(clashMode)
                    .font(.system(size: buttonFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: chevronSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectorBackground()
    }

    #if !os(tvOS)
        private var modeTabBar: some View {
            HStack(spacing: 0) {
                ForEach(commandClient.clashModeList, id: \.self) { mode in
                    Button {
                        withAnimation {
                            clashMode = mode
                        }
                        Task {
                            await setClashMode(mode)
                        }
                    } label: {
                        Text(mode)
                            .font(.system(size: buttonFontSize, weight: .medium))
                            .foregroundStyle(mode == clashMode ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: buttonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if mode == clashMode {
                            selectorCapsule
                                .matchedGeometryEffect(id: "selector", in: tabNamespace)
                        }
                    }
                }
            }
            .selectorBackground()
        }

        private var tabBarContent: some View {
            HStack(spacing: 0) {
                ForEach(commandClient.clashModeList, id: \.self) { mode in
                    Text(mode)
                        .font(.system(size: buttonFontSize, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: buttonHeight)
                }
            }
        }

        @ViewBuilder
        private var selectorCapsule: some View {
            if #available(iOS 26.0, macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.1))
            }
        }
    #endif

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

    #if !os(tvOS)
        private var tabsFit: Bool {
            tabBarWidth > 0 && tabBarWidth <= availableWidth
        }
    #endif

    private var shouldShowPicker: Bool {
        commandClient.clashModeList.count > 1
    }

    private nonisolated func setClashMode(_ newMode: String) async {
        do {
            try LibboxNewStandaloneCommandClient()!.setClashMode(newMode)
        } catch {
            await MainActor.run {
                alert = AlertState(action: "set clash mode", error: error)
            }
        }
    }
}

#if !os(tvOS)
    private struct AvailableWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct TabBarWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
#endif
