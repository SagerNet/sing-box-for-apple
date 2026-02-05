import AppIntents
import SwiftUI
import WidgetKit

struct ServiceToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: WidgetAppConfiguration.widgetControlKind,
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "sing-box",
                isOn: value,
                action: ToggleServiceControlIntent()
            ) { isOn in
                Label(isOn ? "Running" : "Stopped", systemImage: "shippingbox.fill")
                    .controlWidgetActionHint(isOn ? "Stop" : "Start")
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
            try await WidgetTunnelControl.currentIsStarted()
        }
    }
}

struct ToggleServiceControlIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Toggle sing-box"

    @Parameter(title: "Running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await WidgetTunnelControl.setStarted(value)
        return .result()
    }
}
