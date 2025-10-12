import Library
import SwiftUI

@MainActor
final class SettingViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var taiwanFlagAvailable = false

    nonisolated func checkTaiwanFlagAvailability() async {
        let available: Bool
        if ApplicationLibrary.inPreview {
            available = true
        } else {
            available = !DeviceCensorship.isChinaDevice()
        }
        await MainActor.run {
            taiwanFlagAvailable = available
            isLoading = false
        }
    }
}
