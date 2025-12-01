import Foundation
import Library
import SwiftUI

@MainActor
final class ServiceLogViewModel: BaseViewModel {
    @Published var content = ""

    override init() {
        super.init()
        isLoading = true
    }

    var isEmpty: Bool {
        content.isEmpty
    }

    nonisolated func loadContent() async {
        var content = ""
        do {
            content = try String(contentsOf: FilePath.cacheDirectory.appendingPathComponent("stderr.log"))
        } catch {}
        if content.isEmpty {
            do {
                content = try String(contentsOf: FilePath.cacheDirectory.appendingPathComponent("stderr.log.old"))
            } catch {}
        }
        #if DEBUG
            if content.isEmpty {
                content = "Empty content"
            }
        #endif
        if !content.isEmpty {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let machineName = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            var deviceInfo = String("Machine: ") + machineName + "\n"
            #if os(iOS)
                await deviceInfo += String("System: ") + (UIDevice.current.systemName) + " " + (UIDevice.current.systemVersion) + "\n"
            #elseif os(macOS)
                deviceInfo += String("System: ") + "macOS " + ProcessInfo().operatingSystemVersionString + "\n"
            #endif
            content = deviceInfo + "\n" + content
        }
        await MainActor.run { [content] in
            self.content = content
            isLoading = false
        }
    }

    nonisolated func deleteContent(dismiss: DismissAction) async {
        try? FileManager.default.removeItem(at: FilePath.cacheDirectory.appendingPathComponent("stderr.log"))
        try? FileManager.default.removeItem(at: FilePath.cacheDirectory.appendingPathComponent("stderr.log.old"))
        await MainActor.run {
            dismiss()
            isLoading = true
        }
    }

    func generateShareFile() throws -> URL {
        try content.generateShareFile(name: "service.log")
    }
}
