import Library
import SwiftUI

@MainActor
final class SettingViewModel: BaseViewModel {
    @Published var taiwanFlagAvailable = false

    override init() {
        super.init()
        isLoading = true
    }

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
