
import StoreKit
import SwiftUI

public struct SettingView: View {
    private enum Tabs: Int, CaseIterable, Identifiable {
        public var id: Self {
            self
        }

        #if os(macOS)
            case app
        #endif

        case core, packetTunnel, profileOverride, sponsor

        var label: some View {
            Label(title, systemImage: iconImage)
        }

        var title: String {
            switch self {
            #if os(macOS)
                case .app:
                    return NSLocalizedString("App", comment: "")
            #endif
            case .core:
                return NSLocalizedString("Core", comment: "")
            case .packetTunnel:
                return NSLocalizedString("Packet Tunnel", comment: "")
            case .profileOverride:
                return NSLocalizedString("Profile Override", comment: "")
            case .sponsor:
                return NSLocalizedString("Sponsor", comment: "")
            }
        }

        private var iconImage: String {
            switch self {
            #if os(macOS)
                case .app:
                    return "app.badge.fill"
            #endif
            case .core:
                return "shippingbox.fill"
            case .packetTunnel:
                return "aspectratio.fill"
            case .profileOverride:
                return "square.dashed.inset.filled"
            case .sponsor:
                return "heart.fill"
            }
        }

        @MainActor
        var contentView: some View {
            viewBuilder {
                switch self {
                #if os(macOS)
                    case .app:
                        MacAppView()
                #endif
                case .core:
                    CoreView()
                case .packetTunnel:
                    PacketTunnelView()
                case .profileOverride:
                    ProfileOverrideView()
                case .sponsor:
                    SponsorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #if os(iOS)
                .background(Color(uiColor: .systemGroupedBackground))
            #endif
        }

        @MainActor
        var navigationLink: some View {
            NavigationLink {
                contentView
            } label: {
                label
            }
        }
    }

    @State private var isLoading = true
    @State private var taiwanFlagAvailable = false

    public init() {}
    public var body: some View {
        FormView {
            #if os(macOS)
                Tabs.app.navigationLink
            #endif
            ForEach([Tabs.core, Tabs.packetTunnel, Tabs.profileOverride]) { it in
                it.navigationLink
            }
            Section("About") {
                Link(destination: URL(string: "https://sing-box.sagernet.org/")!) {
                    Label("Documentation", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                #if !os(tvOS)
                    RequestReviewButton {
                        Label("Rate on the App Store", systemImage: "text.bubble.fill")
                    }
                #endif
                Tabs.sponsor.navigationLink
            }
            Section("Debug") {
                NavigationLink {
                    ServiceLogView()
                } label: {
                    Label("Service Log", systemImage: "doc.on.clipboard")
                }
                FormTextItem("Taiwan Flag Available", "touchid") {
                    if isLoading {
                        Text("Loading...")
                            .onAppear {
                                Task.detached {
                                    taiwanFlagAvailable = !DeviceCensorship.isChinaDevice()
                                    isLoading = false
                                }
                            }
                    } else {
                        Text(taiwanFlagAvailable.description)
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
