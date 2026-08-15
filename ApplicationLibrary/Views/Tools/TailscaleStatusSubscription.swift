import Library
import SwiftUI

public extension View {
    func tailscaleStatusSubscription(
        _ viewModel: TailscaleStatusViewModel,
        environments: ExtensionEnvironments,
        peerStore: TailscaleSSHPeerStore
    ) -> some View {
        modifier(TailscaleStatusSubscriptionModifier(environments: environments, peerStore: peerStore, viewModel: viewModel))
    }
}

private struct TailscaleStatusSubscriptionModifier: ViewModifier {
    @ObservedObject var environments: ExtensionEnvironments
    let peerStore: TailscaleSSHPeerStore
    let viewModel: TailscaleStatusViewModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                viewModel.peerStore = peerStore
                viewModel.environments = environments
            }
            .modifier(ConnectionLifecycleObserver(
                profile: environments.extensionProfile,
                remoteServerID: environments.remoteServer?.id,
                onActive: { viewModel.subscribe() },
                onInactive: { viewModel.cancel() }
            ))
    }
}
