import Library
import SwiftUI

@MainActor
public struct ToolsView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @StateObject private var viewModel = SettingViewModel()
    #if os(iOS)
        @State private var showCrashReportList = false
        @State private var showOOMReportList = false
    #endif

    public init() {}

    public var body: some View {
        FormView {
            Section("Network") {
                FormNavigationLink {
                    NetworkQualityView()
                } label: {
                    Label("Network Quality", systemImage: "network")
                }
                FormNavigationLink {
                    STUNTestView()
                } label: {
                    Label("STUN Test", systemImage: "arrow.triangle.swap")
                }
            }

            Section("Debug") {
                #if os(iOS)
                    NavigationLink(isActive: $showCrashReportList) {
                        CrashReportListView()
                    } label: {
                        Label("Crash Report", systemImage: "ladybug.fill")
                            .badge(environments.crashReportManager.unreadCount)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .reportReceived)) { notification in
                        Task {
                            try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)
                            if let reportType = notification.object as? ReportType {
                                switch reportType {
                                case .crash:
                                    showCrashReportList = true
                                case .oom:
                                    showOOMReportList = true
                                }
                            }
                        }
                    }
                    NavigationLink(isActive: $showOOMReportList) {
                        OOMReportListView()
                    } label: {
                        Label("OOM Report", systemImage: "memorychip")
                            .badge(environments.oomReportManager.unreadCount)
                    }
                #else
                    FormNavigationLink {
                        CrashReportListView()
                    } label: {
                        #if os(tvOS)
                            HStack {
                                Label("Crash Report", systemImage: "ladybug.fill")
                                Spacer()
                                if environments.crashReportManager.unreadCount > 0 {
                                    Text(verbatim: "\(environments.crashReportManager.unreadCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        #else
                            Label("Crash Report", systemImage: "ladybug.fill")
                                .badge(environments.crashReportManager.unreadCount)
                        #endif
                    }
                #endif
                #if !os(iOS)
                    FormNavigationLink {
                        OOMReportListView()
                    } label: {
                        #if os(tvOS)
                            HStack {
                                Label("OOM Report", systemImage: "memorychip")
                                Spacer()
                                if environments.oomReportManager.unreadCount > 0 {
                                    Text(verbatim: "\(environments.oomReportManager.unreadCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        #else
                            Label("OOM Report", systemImage: "memorychip")
                                .badge(environments.oomReportManager.unreadCount)
                        #endif
                    }
                #endif
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
