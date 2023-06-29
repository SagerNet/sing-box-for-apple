import AppIntents
import Foundation
import Libbox
import Library

struct StartServiceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start sing-box"

    static var description =
        IntentDescription("Start or reload sing-box servie with specified profile")

    static var parameterSummary: some ParameterSummary {
        Summary("Start sing-box service with profile \(\.$profile).")
    }

    @Parameter(title: "Profile", optionsProvider: ProfileProvider())
    var profile: String

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            throw NSError(domain: "NetworkExtension not installed", code: 0)
        }
        let profileList = try ProfileManager.list()
        let specifiedProfile = profileList.first { $0.name == profile }
        var profileChanged = false
        if let specifiedProfile {
            if SharedPreferences.selectedProfileID != specifiedProfile.id! {
                SharedPreferences.selectedProfileID = specifiedProfile.id!
                profileChanged = true
            }
        } else if profile != "default" {
            throw NSError(domain: "Specified profile not found: \(profile)", code: 0)
        }
        if extensionProfile.status == .connected {
            if !profileChanged {
                return .result()
            }
            try LibboxNewStandaloneCommandClient(FilePath.sharedDirectory.relativePath)?.serviceReload()
        } else if extensionProfile.status.isConnected {
            extensionProfile.stop()
            try await Task.sleep(nanoseconds: UInt64(100 * Double(NSEC_PER_MSEC)))
            try await extensionProfile.start()
        } else {
            try await extensionProfile.start()
        }
        return .result()
    }
}

struct RestartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart sing-box"

    static var description =
        IntentDescription("Restart sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Restart sing-box service")
    }

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result()
        }
        if extensionProfile.status == .connected {
            try LibboxNewStandaloneCommandClient(FilePath.sharedDirectory.relativePath)?.serviceReload()
        } else if extensionProfile.status.isConnected {
            extensionProfile.stop()
            try await Task.sleep(nanoseconds: UInt64(100 * Double(NSEC_PER_MSEC)))
            try await extensionProfile.start()
        } else {
            try await extensionProfile.start()
        }
        return .result()
    }
}

struct StopServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop sing-box"

    static var description =
        IntentDescription("Stop sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Stop sing-box service")
    }

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result()
        }
        extensionProfile.stop()
        return .result()
    }
}

struct ToggleServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle sing-box"

    static var description =
        IntentDescription("Toggle sing-box service")

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle sing-box service")
    }

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(value: false)
        }
        if extensionProfile.status.isConnected {
            extensionProfile.stop()
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

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result(value: false)
        }
        return .result(value: extensionProfile.status.isConnected)
    }
}

struct GetCurrentProfile: AppIntent {
    static var title: LocalizedStringResource = "Get current sing-box profile"

    static var description =
        IntentDescription("Get current sing-box profile")

    static var parameterSummary: some ParameterSummary {
        Summary("Get current sing-box profile")
    }

    func perform() async throws -> some IntentResult {
        guard let profile = try ProfileManager.get(SharedPreferences.selectedProfileID) else {
            throw NSError(domain: "No profile selected", code: 0)
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
    func perform() async throws -> some IntentResult {
        guard let profile = try ProfileManager.get(by: profile) else {
            throw NSError(domain: "Specified profile not found: \(profile)", code: 0)
        }
        if profile.type != .remote {
            throw NSError(domain: "Specified profile is not a remote profile", code: 0)
        }
        try profile.updateRemoteProfile()
        return .result()
    }
}

class ProfileProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        var profileNames = try ProfileManager.list().map(\.name)
        if !profileNames.contains("default") {
            profileNames.insert("default", at: 0)
        }
        return profileNames
    }
}

class RemoteProfileProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        try ProfileManager.listRemote().map(\.name)
    }
}
