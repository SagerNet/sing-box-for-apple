import Library
import SwiftUI

public struct SettingView: View {
    private enum Tabs: Int, CaseIterable, Identifiable {
        var id: Self {
            self
        }

        #if os(macOS)
            case app
        #endif

        case core, packetTunnel, onDemandRules, profileOverride, sponsors

        var label: some View {
            Label(title, systemImage: iconImage)
        }

        var title: String {
            switch self {
            #if os(macOS)
                case .app:
                    return String(localized: "App")
            #endif
            case .core:
                return String(localized: "Core")
            case .packetTunnel:
                return String(localized: "Packet Tunnel")
            case .onDemandRules:
                return String(localized: "On Demand Rules")
            case .profileOverride:
                return String(localized: "Profile Override")
            case .sponsors:
                return String(localized: "Sponsors")
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
            case .onDemandRules:
                return "filemenu.and.selection"
            case .profileOverride:
                return "square.dashed.inset.filled"
            case .sponsors:
                return "heart.fill"
            }
        }

        @MainActor
        var contentView: some View {
            Group {
                switch self {
                #if os(macOS)
                    case .app:
                        AppView()
                #endif
                case .core:
                    CoreView()
                case .packetTunnel:
                    PacketTunnelView()
                case .onDemandRules:
                    OnDemandRulesView()
                case .profileOverride:
                    ProfileOverrideView()
                case .sponsors:
                    SponsorsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            #if os(iOS)
                .background(Color(uiColor: .systemGroupedBackground))
            #endif
        }

        @MainActor
        var navigationLink: some View {
            FormNavigationLink {
                contentView
            } label: {
                label
            }
        }
    }

    @StateObject private var viewModel = SettingViewModel()

    public init() {}
    public var body: some View {
        FormView {
            #if os(macOS)
                Tabs.app.navigationLink
            #endif
            ForEach([Tabs.core, Tabs.packetTunnel, Tabs.onDemandRules, Tabs.profileOverride]) { it in
                it.navigationLink
            }
            #if !os(tvOS)
                Section("About") {
                    Link(destination: URL(string: String(localized: "https://sing-box.sagernet.org/"))!) {
                        Label("Documentation", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .contextMenu {
                        Link(destination: URL(string: String(localized: "https://sing-box.sagernet.org/changelog/"))!) {
                            Text("Changelog")
                        }
                        Link(destination: URL(string: String(localized: "https://sing-box.sagernet.org/configuration/"))!) {
                            Text("Configuration")
                        }
                    }
                    Link(destination: URL(string: String("https://github.com/SagerNet/sing-box"))!) {
                        Label("Source Code", systemImage: "pills.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .contextMenu {
                        Link(destination: URL(string: String("https://github.com/SagerNet/sing-box/releases"))!) {
                            Text("Releases")
                        }
                    }
                    RequestReviewButton {
                        Label("Rate on the App Store", systemImage: "text.bubble.fill")
                    }
                    #if os(macOS)
                        if Variant.useSystemExtension {
                            Tabs.sponsors.navigationLink
                        }
                    #endif
                }
            #endif
            Section("Debug") {
                FormNavigationLink {
                    ServiceLogView()
                } label: {
                    Label("Service Log", systemImage: "doc.on.clipboard")
                }
                FormTextItem("Taiwan Flag Available", "touchid") {
                    if viewModel.isLoading {
                        Text("Loading...")
                            .onAppear {
                                Task.detached {
                                    await viewModel.checkTaiwanFlagAvailability()
                                }
                            }
                    } else {
                        Text(viewModel.taiwanFlagAvailable.toString())
                    }
                }
            }
        }
    }
}
