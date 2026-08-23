import Library
import SwiftUI

@MainActor
public struct PowerReportListView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var powerReportEnabled = false
    @State private var alert: AlertState?
    #if os(tvOS)
        @State private var selectedReport: PowerReport?
    #endif

    public init() {}

    private var manager: PowerReportManager {
        environments.powerReportManager
    }

    public var body: some View {
        FormView {
            if !isLoading {
                FormToggle("Enable Power Report", """
                A report is saved for each service run
                """, $powerReportEnabled, header: "Settings") { newValue in
                    await SharedPreferences.powerReportEnabled.set(newValue)
                    await restartService()
                }

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
                                    PowerReportDetailView(report: report)
                                } label: {
                                    reportLabel(report)
                                }
                            #endif
                        }
                    }
                } header: {
                    Text("Reports")
                }
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
                powerReportEnabled = await SharedPreferences.powerReportEnabled.get()
                isLoading = false
            }
        }
        .navigationTitle("Power Report")
        .alert($alert)
        #if os(tvOS)
            .navigationDestination(item: $selectedReport) { report in
                PowerReportDetailView(report: report)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
        #endif
            .toolbar {
                if !manager.reports.isEmpty {
                    #if os(tvOS)
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
                    #else
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
                    #endif
                }
            }
    }

    private func reportLabel(_ report: PowerReport) -> some View {
        ReportLabel(date: report.date, isRead: report.isRead, origin: report.origin)
    }

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
}
