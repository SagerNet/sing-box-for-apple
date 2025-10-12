import Libbox
import Library
import SwiftUI

@MainActor
final class ClashModeViewModel: ObservableObject {
    @Published var clashMode = ""
    @Published var alert: Alert?

    var commandClient: CommandClient?

    var clashModeList: [String] {
        commandClient?.clashModeList ?? []
    }

    var shouldShowPicker: Bool {
        (commandClient?.clashModeList.count ?? 0) > 1
    }

    func setCommandClient(_ client: CommandClient) {
        commandClient = client
        client.$clashMode
            .assign(to: &$clashMode)
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
