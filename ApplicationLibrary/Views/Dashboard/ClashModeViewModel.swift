import Libbox
import Library
import SwiftUI

@MainActor
final class ClashModeViewModel: ObservableObject {
    @Published var clashMode = ""
    @Published var alert: Alert?

    private let commandClient = CommandClient(.clashMode)

    var clashModeList: [String] {
        commandClient.clashModeList
    }

    var shouldShowPicker: Bool {
        commandClient.clashModeList.count > 1
    }

    init() {
        commandClient.$clashMode
            .assign(to: &$clashMode)
    }

    func connect() {
        commandClient.connect()
    }

    func disconnect() {
        commandClient.disconnect()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            connect()
        } else {
            disconnect()
        }
    }

    nonisolated func setClashMode(_ newMode: String) async {
        do {
            try LibboxNewStandaloneCommandClient()!.setClashMode(newMode)
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
