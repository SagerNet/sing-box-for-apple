import AppIntents
import Libbox
import Library
import SwiftUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> ExtensionStatus {
        ExtensionStatus(date: .now, isConnected: false, profileList: [])
    }

    func snapshot(for _: ConfigurationIntent, in _: Context) async -> ExtensionStatus {
        var status = ExtensionStatus(date: .now, isConnected: false, profileList: [])

        do {
            status.isConnected = try await ExtensionProfile.load()?.status.isStrictConnected ?? false

            let profileList = try ProfileManager.list()
            let selectedProfileID = SharedPreferences.selectedProfileID
            for profile in profileList {
                status.profileList.append(ProfileEntry(profile: profile, isSelected: profile.id == selectedProfileID))
            }
        } catch {}

        return status
    }

    func timeline(for intent: ConfigurationIntent, in context: Context) async -> Timeline<ExtensionStatus> {
        await Timeline(entries: [snapshot(for: intent, in: context)], policy: .never)
    }
}

struct ExtensionStatus: TimelineEntry {
    var date: Date
    var isConnected: Bool
    var profileList: [ProfileEntry]
}

struct ProfileEntry {
    let profile: Profile
    let isSelected: Bool
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family

    var status: ExtensionStatus

    var body: some View {
        VStack {
            LabeledContent {
                Text(LibboxVersion())
                    .font(.caption)
            } label: {
                Text("sing-box")
                    .font(.headline)
            }
            VStack {
                viewBuilder {
                    if !status.isConnected {
                        Button(intent: StartServiceIntent()) {
                            Image(systemName: "play.fill")
                        }
                    } else {
                        Button(intent: StopServiceIntent()) {
                            Image(systemName: "stop.fill")
                        }
                    }
                }
                .controlSize(.large)
                .invalidatableContent()
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct WidgetExtension: Widget {
    @State private var extensionProfile: ExtensionProfile?

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "sing-box", intent: ConfigurationIntent.self, provider: Provider()) { status in
            WidgetView(status: status)
        }
        .supportedFamilies([.systemSmall])
    }
}
