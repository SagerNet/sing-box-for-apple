import Libbox
import Library
import SwiftUI

public struct MenuLabel: View {
    @EnvironmentObject private var environments: ExtensionEnvirnments

    public init() {}
    public var body: some View {
//        if let profile = environments.extensionProfile {
//            MenuLabel0().environmentObject(profile)
//        } else {
//        }
    }

    private struct MenuLabel0: View {
        @EnvironmentObject private var environments: ExtensionEnvirnments
        @EnvironmentObject private var extensionProfile: ExtensionProfile
        @StateObject private var commandClient = CommandClient(.status)

        var body: some View {
            HStack {
                if extensionProfile.status.isConnectedStrict, let message = commandClient.status {
                    Image("MenuIcon")
                    Text(" ↑ \(LibboxFormatBytes(message.uplink))/s  ↓ \(LibboxFormatBytes(message.downlink))/s")
                } else {
                    Image("MenuIcon")
                }
            }
            .onAppear {
                commandClient.connect()
            }
            .onChangeCompat(of: extensionProfile.status) { newValue in
                if newValue.isConnectedStrict {
                    commandClient.connect()
                }
            }
        }
    }
}
