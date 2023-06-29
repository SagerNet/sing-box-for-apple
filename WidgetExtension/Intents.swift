import AppIntents
import Library
import WidgetKit

struct ConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("Configuration sing-bix widget.")
}

struct StartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Start sing-box"

    static var description =
        IntentDescription("Start sing-box servie")

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            throw NSError(domain: "NetworkExtension not installed", code: 0)
        }
        if extensionProfile.status == .connected {
            return .result()
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
