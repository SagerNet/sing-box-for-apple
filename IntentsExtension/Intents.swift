import AppIntents
import Foundation
import Library

struct StartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Start sing-box"

    static var description =
        IntentDescription("Start or reload sing-box servie with specified profile")

    static var parameterSummary: some ParameterSummary {
        Summary("Start sing-box service with profile \(\.$profile).")
    }

    @Parameter(title: "Profile", optionsProvider: ProfileProvider())
    var profile: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            throw NSError(domain: "IntentsExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "NetworkExtension not installed")])
        }
        let profileList = try await ProfileManager.list()
        let specifiedProfile = profileList.first { $0.name == profile }
        var profileChanged = false
        if let specifiedProfile {
            let specifiedProfileID = specifiedProfile.mustID
            if await SharedPreferences.selectedProfileID.get() != specifiedProfileID {
                await SharedPreferences.selectedProfileID.set(specifiedProfileID)
                profileChanged = true
            }
        } else if profile != "default" {
            throw NSError(domain: "IntentsExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Specified profile not found: \(profile)")])
        }
        if await extensionProfile.status == .connected {
            if !profileChanged {
                return .result(dialog: "Service is already running")
            }
            try await extensionProfile.reloadService()
        } else if await extensionProfile.status.isConnected {
            try await extensionProfile.restart()
        } else {
            try await extensionProfile.start()
        }
        return .result(dialog: "Service started")
    }
}

struct RestartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart sing-box"

    static var description =
        IntentDescription("Restart sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Restart sing-box service")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(dialog: "Service is not installed")
        }
        if await extensionProfile.status == .connected {
            try await extensionProfile.reloadService()
        } else if await extensionProfile.status.isConnected {
            try await extensionProfile.restart()
        } else {
            try await extensionProfile.start()
        }
        return .result(dialog: "Service restarted")
    }
}

struct StopServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop sing-box"

    static var description =
        IntentDescription("Stop sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Stop sing-box service")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(dialog: "Service is not installed")
        }
        try await extensionProfile.stop()
        return .result(dialog: "Service stopped")
    }
}

struct ToggleServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle sing-box"

    static var description =
        IntentDescription("Toggle sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle sing-box service")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(value: false)
        }
        if await extensionProfile.status.isConnected {
            try await extensionProfile.stop()
            return .result(value: false)

        } else {
            try await extensionProfile.start()
            return .result(value: true)
        }
    }
}

struct GetServiceStatus: AppIntent {
    static var title: LocalizedStringResource = "Get is sing-box service started"

    static var description =
        IntentDescription("Get is sing-box service started")

    static var parameterSummary: some ParameterSummary {
        Summary("Get is sing-box service started")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(value: false)
        }
        return await .result(value: extensionProfile.status.isConnected)
    }
}

struct GetCurrentProfile: AppIntent {
    static var title: LocalizedStringResource = "Get current sing-box profile"

    static var description =
        IntentDescription("Get current sing-box profile")

    static var parameterSummary: some ParameterSummary {
        Summary("Get current sing-box profile")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let profile = try await ProfileManager.get(SharedPreferences.selectedProfileID.get()) else {
            throw NSError(domain: "IntentsExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "No profile selected")])
        }
        return .result(value: profile.name)
    }
}

struct UpdateProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Update sing-box profile"

    static var description =
        IntentDescription("Update specified sing-box profile")

    static var parameterSummary: some ParameterSummary {
        Summary("Update sing-box profile \(\.$profile).")
    }

    @Parameter(title: "Profile", optionsProvider: RemoteProfileProvider())
    var profile: String

    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let profile = try await ProfileManager.get(by: profile) else {
            throw NSError(domain: "IntentsExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Specified profile not found: \(profile)")])
        }
        if profile.type != .remote {
            throw NSError(domain: "IntentsExtension", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Specified profile is not a remote profile")])
        }
        try await profile.updateRemoteProfile()
        return .result(dialog: "Profile updated")
    }
}

class ProfileProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        var profileNames = try await ProfileManager.list().map(\.name)
        if !profileNames.contains("default") {
            profileNames.insert("default", at: 0)
        }
        return profileNames
    }
}

class RemoteProfileProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        try await ProfileManager.listRemote().map(\.name)
    }
}

struct ServiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartServiceIntent(),
            phrases: ["Start \(.applicationName)"],
            shortTitle: "Start",
            systemImageName: "power"
        )
        AppShortcut(
            intent: StopServiceIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: RestartServiceIntent(),
            phrases: ["Restart \(.applicationName)"],
            shortTitle: "Restart",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: ToggleServiceIntent(),
            phrases: ["Toggle \(.applicationName)"],
            shortTitle: "Toggle",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: UpdateProfileIntent(),
            phrases: ["Update \(.applicationName) profile"],
            shortTitle: "Update Profile",
            systemImageName: "arrow.down.circle"
        )
    }
}
