import AppIntents
import Library
import SwiftUI
import WidgetKit

struct ServiceToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ExtensionProfile.controlKind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "sing-box",
                isOn: value,
                action: ToggleServiceIntent()
            ) { isOn in
                Label(isOn ? "Running" : "Stopped", systemImage: "shippingbox.fill")
            }
            .tint(.init(red: CGFloat(Double(69) / 255), green: CGFloat(Double(90) / 255), blue: CGFloat(Double(100) / 255)))
        }
        .displayName("Toggle")
        .description("Start or stop sing-box service.")
    }
}

extension ServiceToggleControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            guard let extensionProfile = try await (ExtensionProfile.load()) else {
                return false
            }
            return extensionProfile.status.isStarted
        }
    }
}

struct ToggleServiceIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Toggle sing-box"

    @Parameter(title: "Running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        guard let extensionProfile = try await (ExtensionProfile.load()) else {
            return .result()
        }
        if value {
            try await extensionProfile.start()
        } else {
            try await extensionProfile.stop()
        }
        return .result()
    }
}
