import Library
import SwiftUI

#if os(macOS)
    private struct SettingsNavigationPathKey: EnvironmentKey {
        static let defaultValue: Binding<NavigationPath>? = nil
    }

    public extension EnvironmentValues {
        var settingsNavigationPath: Binding<NavigationPath>? {
            get { self[SettingsNavigationPathKey.self] }
            set { self[SettingsNavigationPathKey.self] = newValue }
        }
    }
#endif

#if os(macOS)
    public enum SettingsPage: Hashable {
        case app
        case core, packetTunnel, onDemandRules, profileOverride, sponsors
    }
#endif

public struct SettingView: View {
    private enum Tabs: Int, CaseIterable, Identifiable {
        var id: Self {
            self
        }

        case app, core, packetTunnel, onDemandRules, profileOverride, sponsors

        #if os(macOS)
            var page: SettingsPage {
                switch self {
                case .app:
                    return .app
                case .core:
                    return .core
                case .packetTunnel:
                    return .packetTunnel
                case .onDemandRules:
                    return .onDemandRules
                case .profileOverride:
                    return .profileOverride
                case .sponsors:
                    return .sponsors
                }
            }
        #endif

        var label: some View {
            Label(title, systemImage: iconImage)
        }

        var title: String {
            switch self {
            case .app:
                return String(localized: "App")
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
            case .app:
                return "app.badge.fill"
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
                case .app:
                    AppView()
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
            #if os(macOS)
                FormNavigationLink(value: page) {
                    label
                }
            #else
                FormNavigationLink {
                    contentView
                } label: {
                    label
                }
            #endif
        }
    }

    #if os(macOS)
        @MainActor
        @ViewBuilder
        private static func destinationView(for page: SettingsPage) -> some View {
            Group {
                switch page {
                case .app:
                    AppView()
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
        }
    #endif

    @StateObject private var viewModel = SettingViewModel()
    public init() {}
    public var body: some View {
        FormView {
            Section {
                ForEach([Tabs.app, Tabs.core, Tabs.packetTunnel, Tabs.onDemandRules, Tabs.profileOverride]) { it in
                    it.navigationLink
                }
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
        #if os(macOS)
        .formNavigationDestination(for: SettingsPage.self) { page in
            Self.destinationView(for: page)
        }
        #endif
    }
}
