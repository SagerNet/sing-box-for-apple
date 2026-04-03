import Libbox
import Library
import SwiftUI

@MainActor
public struct OOMReportListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    #if os(tvOS)
        @State private var selectedReport: OOMReport?
    #endif
    #if os(macOS)
        @State private var oomKillerEnabled = false
        @State private var oomMemoryLimitMB = 50
        @State private var oomKillerKillConnections = false
        @State private var alert: AlertState?
    #endif

    public init() {}

    private var manager: OOMReportManager {
        environments.oomReportManager
    }

    public var body: some View {
        FormView {
            if !isLoading {
                Section {
                    if manager.reports.isEmpty {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.reports) { report in
                            #if os(tvOS)
                                Button {
                                    selectedReport = report
                                } label: {
                                    reportLabel(report)
                                }
                            #else
                                FormNavigationLink {
                                    OOMReportDetailView(report: report)
                                } label: {
                                    reportLabel(report)
                                }
                            #endif
                        }
                    }
                } header: {
                    Text("Reports")
                } footer: {
                    #if os(macOS)
                        Text("When memory limit is enabled, you will receive a report if the service memory exceeds the limit. You can also manually trigger report collection.")
                    #else
                        Text("You will receive a report when the service runs out of memory. You can also manually trigger report collection.")
                    #endif
                }

                #if os(macOS)
                    Section {
                        FormToggle("Enable Memory Limit", """
                        Provide a soft memory limit for the service. The service will perform multiple processes to try to stay within this memory limit.
                        """, $oomKillerEnabled) { newValue in
                            await SharedPreferences.oomKillerEnabled.set(newValue)
                            await restartService()
                        }

                        if oomKillerEnabled {
                            Picker("Memory Limit", selection: $oomMemoryLimitMB) {
                                ForEach(Self.memoryLimitOptions, id: \.self) { value in
                                    Text(LibboxFormatMemoryBytes(Int64(value) * 1024 * 1024))
                                        .tag(value)
                                }
                            }
                            .onChange(of: oomMemoryLimitMB) { _ in
                                Task {
                                    await SharedPreferences.oomMemoryLimitMB.set(oomMemoryLimitMB)
                                    await restartService()
                                }
                            }

                            FormToggle("Kill Connections", """
                            Kill all connections to free memory when the service memory exceeds the limit.
                            """, $oomKillerKillConnections) { newValue in
                                await SharedPreferences.oomKillerKillConnections.set(newValue)
                                await restartService()
                            }
                        }
                    } header: {
                        Text("Settings")
                    }
                #endif
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .onAppear {
            Task {
                await manager.refresh()
                #if os(macOS)
                    oomKillerEnabled = await SharedPreferences.oomKillerEnabled.get()
                    let storedLimit = await SharedPreferences.oomMemoryLimitMB.get()
                    if Self.memoryLimitOptions.contains(storedLimit) {
                        oomMemoryLimitMB = storedLimit
                    } else {
                        oomMemoryLimitMB = Self.memoryLimitOptions.first!
                        await SharedPreferences.oomMemoryLimitMB.set(oomMemoryLimitMB)
                    }
                    oomKillerKillConnections = await SharedPreferences.oomKillerKillConnections.get()
                #endif
                isLoading = false
            }
        }
        .navigationTitle("OOM Report")
        #if os(macOS)
            .alert($alert)
        #endif
        #if os(tvOS)
        .navigationDestination(item: $selectedReport) { report in
            OOMReportDetailView(report: report)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }
        #endif
        .toolbar {
            #if os(tvOS)
                if !manager.reports.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await manager.deleteAll()
                            }
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
                if let profile = environments.extensionProfile {
                    ToolbarItem(placement: .confirmationAction) {
                        OOMReportTriggerButton(manager: manager, profile: profile)
                    }
                }
            #else
                if let profile = environments.extensionProfile {
                    OOMReportToolbarMenu(manager: manager, profile: profile)
                } else if !manager.reports.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await manager.deleteAll()
                            }
                        } label: {
                            Label("Delete All", systemImage: "trash.fill")
                        }
                    } label: {
                        Label("Others", systemImage: "line.3.horizontal.circle")
                    }
                }
            #endif
        }
    }

    private func reportLabel(_ report: OOMReport) -> some View {
        ReportLabel(date: report.date, isRead: report.isRead, origin: report.origin)
    }

    #if os(macOS)
        private static let memoryLimitOptions = [50, 100, 200, 300, 500, 750, 1024]

        private func restartService() async {
            guard let profile = environments.extensionProfile, profile.status.isConnected else {
                return
            }
            do {
                try await profile.restart()
            } catch {
                alert = AlertState(action: "restart service", error: error)
            }
        }
    #endif
}

#if os(tvOS)
    private struct OOMReportTriggerButton: View {
        let manager: OOMReportManager
        @ObservedObject var profile: ExtensionProfile
        @State private var alert: AlertState?

        var body: some View {
            Button {
                triggerOOMReport(profile: profile, manager: manager, alert: &alert)
            } label: {
                Image(systemName: "memorychip")
            }
            .alert($alert)
        }
    }
#else
    private struct OOMReportToolbarMenu: View {
        let manager: OOMReportManager
        @ObservedObject var profile: ExtensionProfile
        @State private var alert: AlertState?

        var body: some View {
            Menu {
                Button {
                    triggerOOMReport(profile: profile, manager: manager, alert: &alert)
                } label: {
                    Label("Fetch Memory Report", systemImage: "memorychip")
                }
                if !manager.reports.isEmpty {
                    Button(role: .destructive) {
                        Task {
                            await manager.deleteAll()
                        }
                    } label: {
                        Label("Delete All", systemImage: "trash.fill")
                    }
                }
            } label: {
                Label("Others", systemImage: "line.3.horizontal.circle")
            }
            .alert($alert)
        }
    }
#endif

@MainActor
private func triggerOOMReport(profile: ExtensionProfile, manager: OOMReportManager, alert: inout AlertState?) {
    guard profile.status.isConnectedStrict else {
        alert = AlertState(errorMessage: String(localized: "Service not started"))
        return
    }
    try? LibboxNewStandaloneCommandClient()?.triggerOOMReport()
    Task {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        await manager.refresh()
    }
}
