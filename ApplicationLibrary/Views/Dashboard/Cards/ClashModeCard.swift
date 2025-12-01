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
            DashboardCardView(title: String(localized: "Mode"), isHalfWidth: false) {
                Picker("", selection: Binding(get: {
                    clashMode
                }, set: { newMode in
                    clashMode = newMode
                    Task {
                        await setClashMode(newMode)
                    }
                })) {
                    ForEach(commandClient.clashModeList, id: \.self) { mode in
                        Text(mode)
                    }
                }
                .pickerStyle(.segmented)
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
