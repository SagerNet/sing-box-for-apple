import Library
import SwiftUI

struct PacketTunnelView: View {
    @State private var isLoading = true

    @State private var ignoreMemoryLimit = false

    @State private var includeAllNetworks = false
    @State private var excludeAPNs = false
    @State private var excludeCellularServices = false
    @State private var excludeLocalNetworks = false
    @State private var enforceRoutes = false

    init() {}
    var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    FormToggle("Ignore Memory Limit", """
                    Do not enforce memory limits on sing-box. Will cause OOM on non-jailbroken iOS and tvOS devices.
                    """, $ignoreMemoryLimit) { newValue in
                        await SharedPreferences.ignoreMemoryLimit.set(newValue)
                    }

                    #if !os(tvOS)
                        FormToggle("includeAllNetworks", """
                        If this property is true, the system routes network traffic through the tunnel except traffic for designated system services necessary for maintaining expected device functionality. You can exclude some types of traffic using the **excludeAPNs**, **excludeLocalNetworks**, and **excludeCellularServices** properties in combination with this property.

                        when enabled, the default TUN stack is changed to `gvisor`, and the `system` and `mixed` stacks are not available.

                        [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3131931-includeallnetworks)
                        """, $includeAllNetworks) { newValue in
                            await SharedPreferences.includeAllNetworks.set(newValue)
                        }

                        FormToggle("excludeAPNs", """
                        If this property is true, the system excludes Apple Push Notification services (APNs) traffic, but only when the **includeAllNetworks** property is also true.

                        [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140516-excludeapns)
                        """, $excludeAPNs) { newValue in
                            await SharedPreferences.excludeAPNs.set(newValue)
                        }

                        FormToggle("excludeCellularServices", """
                        If this property is true, the system excludes cellular services — such as Wi-Fi Calling, MMS, SMS, and Visual Voicemail — but only when the **includeAllNetworks** property is also true. This property doesn’t impact services that use the cellular network only — such as VoLTE — which the system automatically excludes.

                        [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140517-excludecellularservices)
                        """, $excludeCellularServices) { newValue in
                            await SharedPreferences.excludeCellularServices.set(newValue)
                        }

                        FormToggle("excludeLocalNetworks", """
                        If this property is true, the system excludes network connections to hosts on the local network — such as AirPlay, AirDrop, and CarPlay — but only when the **includeAllNetworks** or **enforceRoutes** property is also true.

                        [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3143658-excludelocalnetworks)
                        """, $excludeLocalNetworks) { newValue in
                            await SharedPreferences.excludeLocalNetworks.set(newValue)
                        }

                        FormToggle("enforceRoutes", """
                        If this property is true when the **includeAllNetworks** property is false, the system scopes the included routes to the VPN and the excluded routes to the current primary network interface. This property supersedes the system routing table and scoping operations by apps.

                        If you set both the **enforceRoutes** and **excludeLocalNetworks** properties to true, the system excludes network connections to hosts on the local network.

                        [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3689459-enforceroutes)
                        """, $enforceRoutes) { newValue in
                            await SharedPreferences.enforceRoutes.set(newValue)
                        }

                    #endif

                    FormButton {
                        Task {
                            await SharedPreferences.resetPacketTunnel()
                            isLoading = true
                        }
                    } label: {
                        Label("Reset", systemImage: "eraser.fill")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Packet Tunnel")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadSettings() async {
        ignoreMemoryLimit = await SharedPreferences.ignoreMemoryLimit.get()
        #if !os(tvOS)
            includeAllNetworks = await SharedPreferences.includeAllNetworks.get()
            excludeAPNs = await SharedPreferences.excludeAPNs.get()
            excludeCellularServices = await SharedPreferences.excludeCellularServices.get()
            excludeLocalNetworks = await SharedPreferences.excludeLocalNetworks.get()
            enforceRoutes = await SharedPreferences.enforceRoutes.get()
        #endif
        isLoading = false
    }
}
