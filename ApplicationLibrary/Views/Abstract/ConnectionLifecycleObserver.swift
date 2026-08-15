import Library
import SwiftUI

struct ConnectionLifecycleObserver: ViewModifier {
    var profile: ExtensionProfile?
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    func body(content: Content) -> some View {
        content.background {
            if let profile {
                LocalServiceLifecycleTrigger(profile: profile, remoteServerID: remoteServerID, onActive: onActive, onInactive: onInactive)
            } else {
                RemoteServiceLifecycleTrigger(remoteServerID: remoteServerID, onActive: onActive, onInactive: onInactive)
            }
        }
    }
}

private struct LocalServiceLifecycleTrigger: View {
    @ObservedObject var profile: ExtensionProfile
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                if remoteServerID != nil || profile.status.isConnectedStrict {
                    onActive()
                }
            }
            .onChangeCompat(of: remoteServerID) { newValue in
                onInactive()
                if newValue != nil || profile.status.isConnectedStrict {
                    onActive()
                }
            }
            .onChangeCompat(of: profile.status) { status in
                guard remoteServerID == nil else { return }
                if status.isConnectedStrict {
                    onActive()
                } else {
                    onInactive()
                }
            }
    }
}

private struct RemoteServiceLifecycleTrigger: View {
    var remoteServerID: Int64?
    var onActive: () -> Void
    var onInactive: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear {
                if remoteServerID != nil {
                    onActive()
                }
            }
            .onChangeCompat(of: remoteServerID) { newValue in
                onInactive()
                if newValue != nil {
                    onActive()
                }
            }
    }
}
