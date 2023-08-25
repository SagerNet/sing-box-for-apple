import Libbox
import Library
import SwiftUI

public struct ClashModeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var commandClient = CommandClient(.clashMode)
    @State private var clashMode = ""
    @State private var alert: Alert?

    public init() {}
    public var body: some View {
        VStack {
            if commandClient.clashModeList.count > 1 {
                Picker("", selection: Binding(get: {
                    clashMode
                }, set: { newMode in
                    clashMode = newMode
                    Task.detached {
                        await setMode(newMode)
                    }
                }), content: {
                    ForEach(commandClient.clashModeList, id: \.self) { it in
                        Text(it)
                    }
                })
                .pickerStyle(.segmented)
                .padding([.top], 8)
            }
        }
        .onReceive(commandClient.$clashMode) { newMode in
            clashMode = newMode
        }
        .padding([.leading, .trailing])
        .onAppear {
            commandClient.connect()
        }
        .onDisappear {
            commandClient.disconnect()
        }
        .onChangeCompat(of: scenePhase) { newValue in
            if newValue == .active {
                commandClient.connect()
            } else {
                commandClient.disconnect()
            }
        }
        .alertBinding($alert)
    }

    private func setMode(_ newMode: String) {
        do {
            try LibboxNewStandaloneCommandClient()!.setClashMode(newMode)
        } catch {
            alert = Alert(error)
        }
    }
}
