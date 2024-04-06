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

    public init() {}
    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    FormSection {
                        Toggle("Ignore Memory Limit", isOn: $ignoreMemoryLimit)
                            .onChangeCompat(of: ignoreMemoryLimit) { newValue in
                                Task {
                                    await SharedPreferences.ignoreMemoryLimit.set(newValue)
                                }
                            }
                    } footer: {
                        Text("Do not enforce memory limits on sing-box. Will cause OOM on non-jailbroken iOS and tvOS devices.")
                    }

                    #if !os(tvOS)

                        FormSection {
                            Toggle("includeAllNetworks", isOn: $includeAllNetworks)
                                .onChangeCompat(of: includeAllNetworks) { newValue in
                                    Task {
                                        await SharedPreferences.includeAllNetworks.set(newValue)
                                    }
                                }
                        } footer: {
                            Text("""
                            If this property is true, the system routes network traffic through the tunnel except traffic for designated system services necessary for maintaining expected device functionality. You can exclude some types of traffic using the **excludeAPNs**, **excludeLocalNetworks**, and **excludeCellularServices** properties in combination with this property.

                            [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3131931-includeallnetworks)
                            """)
                            .multilineTextAlignment(.leading)
                        }

                        FormSection {
                            Toggle("excludeAPNs", isOn: $excludeAPNs)
                                .onChangeCompat(of: excludeAPNs) { newValue in
                                    Task {
                                        await SharedPreferences.excludeAPNs.set(newValue)
                                    }
                                }
                        } footer: {
                            Text("""
                            If this property is true, the system excludes Apple Push Notification services (APNs) traffic, but only when the **includeAllNetworks** property is also true.

                            [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140516-excludeapns)
                            """)
                        }

                        FormSection {
                            Toggle("excludeCellularServices", isOn: $excludeCellularServices)
                                .onChangeCompat(of: excludeCellularServices) { newValue in
                                    Task {
                                        await SharedPreferences.excludeCellularServices.set(newValue)
                                    }
                                }
                        } footer: {
                            Text("""
                            If this property is true, the system excludes cellular services — such as Wi-Fi Calling, MMS, SMS, and Visual Voicemail — but only when the **includeAllNetworks** property is also true. This property doesn’t impact services that use the cellular network only — such as VoLTE — which the system automatically excludes.

                            [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140517-excludecellularservices)
                            """)
                        }

                        FormSection {
                            Toggle("excludeLocalNetworks", isOn: $excludeLocalNetworks)
                                .onChangeCompat(of: excludeLocalNetworks) { newValue in
                                    Task {
                                        await SharedPreferences.excludeLocalNetworks.set(newValue)
                                    }
                                }
                        } footer: {
                            Text("""
                            If this property is true, the system excludes network connections to hosts on the local network — such as AirPlay, AirDrop, and CarPlay — but only when the **includeAllNetworks** or **enforceRoutes** property is also true.

                            [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3143658-excludelocalnetworks)
                            """)
                        }

                        FormSection {
                            Toggle("enforceRoutes", isOn: $enforceRoutes)
                                .onChangeCompat(of: enforceRoutes) { newValue in
                                    Task {
                                        await SharedPreferences.enforceRoutes.set(newValue)
                                    }
                                }
                        } footer: {
                            Text("""
                            If this property is true when the **includeAllNetworks** property is false, the system scopes the included routes to the VPN and the excluded routes to the current primary network interface. This property supersedes the system routing table and scoping operations by apps.

                            If you set both the **enforceRoutes** and **excludeLocalNetworks** properties to true, the system excludes network connections to hosts on the local network.

                            [Apple Documentation](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3689459-enforceroutes)
                            """)
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
