import Libbox
import Library
import SwiftUI

public struct ClashModeCard: View {
    @EnvironmentObject private var commandClient: CommandClient
    @State private var clashMode: String = ""
    @State private var alert: AlertState?

    public init() {}

    public var body: some View {
        if shouldShowPicker {
            DashboardCardView(title: "", isHalfWidth: false) {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardCardHeader(icon: "circle.grid.2x2.fill", title: "Mode")
                    modeMenu
                }
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

    private var shouldShowPicker: Bool {
        commandClient.clashModeList.count > 1
    }

    private nonisolated func setClashMode(_ newMode: String) async {
        do {
            try LibboxNewStandaloneCommandClient()!.setClashMode(newMode)
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }
}
