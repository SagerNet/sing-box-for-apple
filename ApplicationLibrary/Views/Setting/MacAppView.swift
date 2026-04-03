import Library
import SwiftUI

#if os(macOS)
    import AppKit
    import ServiceManagement
#endif

public struct AppView: View {
    private struct LanguageOption: Hashable {
        let code: String?
        let name: String
    }

    private static var supportedLanguages: [LanguageOption] {
        var options = [LanguageOption(code: nil, name: String(localized: "System Default"))]
        options.append(contentsOf: configuredLanguageCodes().map { code in
            let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
            return LanguageOption(code: code, name: name)
        })
        return options
    }

    @State private var isLoading = true
    @State private var selectedLanguage: String?
    @State private var cacheSize: Int64 = 0
    @State private var cacheSizeText = ""

    #if os(macOS)
        @State private var startAtLogin = false
        @Environment(\.showMenuBarExtra) private var showMenuBarExtra
        @Environment(\.menuBarExtraSpeedMode) private var menuBarExtraSpeedMode
        @State private var menuBarExtraInBackground = false
        @State private var systemExtensionInstalled = false
        @State private var helperStatusLoaded = false
        @State private var rootHelperRegistrationStatus: SMAppService.Status = .notRegistered
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var updateManager: UpdateManager
        @State private var updateTrack: UpdateTrack = .stable
        @State private var checkUpdateEnabled = false
    #endif

    @State private var alert: AlertState?

    public init() {}
    public var body: some View {
        Group {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Self.supportedLanguages, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }
                    .onChangeCompat(of: selectedLanguage) { newValue in
                        updateLanguage(newValue)
                    }

                    #if os(macOS)
                        FormToggle("Start At Login", "Launch the application when the system is logged in. If enabled at the same time as `Show in Menu Bar` and `Keep Menu Bar in Background`, the application interface will not be opened automatically.", $startAtLogin) { newValue in
                            updateLoginItems(newValue)
                        }

                        Toggle("Show in Menu Bar", isOn: showMenuBarExtra)
                            .onChangeCompat(of: showMenuBarExtra.wrappedValue) { newValue in
                                Task {
                                    await SharedPreferences.showMenuBarExtra.set(newValue)
                                    if !newValue {
                                        menuBarExtraInBackground = false
                                    }
                                }
                            }

                        if showMenuBarExtra.wrappedValue {
                            Picker("Real-time Speed", selection: menuBarExtraSpeedMode) {
                                ForEach(MenuBarExtraSpeedMode.allCases, id: \.rawValue) { mode in
                                    Text(mode.name).tag(mode.rawValue)
                                }
                            }
                            .onChangeCompat(of: menuBarExtraSpeedMode.wrappedValue) { newValue in
                                Task {
                                    await SharedPreferences.menuBarExtraSpeedMode.set(newValue)
                                }
                            }

                            Toggle("Keep Menu Bar in Background", isOn: $menuBarExtraInBackground)
                                .onChangeCompat(of: menuBarExtraInBackground) { newValue in
                                    Task {
                                        await SharedPreferences.menuBarExtraInBackground.set(newValue)
                                    }
                                }
                        }

                    #endif

                    FormTextItem("Cache Size", cacheSizeText)
                    if cacheSize > 0 {
                        FormButton(role: .destructive) {
                            Task.detached {
                                let cacheDir = FilePath.cacheDirectory
                                let workingDir = FilePath.workingDirectory
                                if let contents = try? FileManager.default.contentsOfDirectory(
                                    at: cacheDir,
                                    includingPropertiesForKeys: nil
                                ) {
                                    for item in contents {
                                        if item.lastPathComponent == workingDir.lastPathComponent {
                                            continue
                                        }
                                        try? FileManager.default.removeItem(at: item)
                                    }
                                }
                                await MainActor.run {
                                    cacheSize = 0
                                    cacheSizeText = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
                                }
                            }
                        } label: {
                            Label("Clear Cache", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }

                    #if os(macOS)
                        if Variant.useSystemExtension {
                            Section("Update Settings") {
                                Picker("Update Track", selection: $updateTrack) {
                                    Text("Stable").tag(UpdateTrack.stable)
                                    Text("Beta").tag(UpdateTrack.beta)
                                }
                                .onChangeCompat(of: updateTrack) { newValue in
                                    Task {
                                        await updateManager.updateTrackChanged(to: newValue)
                                    }
                                }

                                Toggle("Automatic Update Check", isOn: $checkUpdateEnabled)
                                    .onChangeCompat(of: checkUpdateEnabled) { newValue in
                                        Task {
                                            await SharedPreferences.checkUpdateEnabled.set(newValue)
                                        }
                                    }

                                FormButton {
                                    Task {
                                        do {
                                            if try await updateManager.refreshUpdateInfo() != nil {
                                                await updateManager.showUpdateSheet()
                                            } else {
                                                alert = AlertState(
                                                    title: String(localized: "Check Update"),
                                                    message: String(localized: "No updates available")
                                                )
                                            }
                                        } catch {}
                                    }
                                } label: {
                                    if updateManager.isChecking {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Checking...")
                                        }
                                    } else {
                                        Label("Check Update", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                .disabled(updateManager.isChecking)
                                .contextMenu {
                                    Button("Force Show Latest Version as Update") {
                                        Task {
                                            do {
                                                if try await updateManager.refreshUpdateInfo(force: true) != nil {
                                                    await updateManager.showUpdateSheet()
                                                } else {
                                                    alert = AlertState(
                                                        title: String(localized: "Check Update"),
                                                        message: String(localized: "No updates available")
                                                    )
                                                }
                                            } catch {}
                                        }
                                    }
                                    .disabled(updateManager.isChecking)
                                }

                                if let info = updateManager.updateInfo {
                                    FormButton {
                                        Task {
                                            await updateManager.showUpdateSheet()
                                        }
                                    } label: {
                                        HStack {
                                            Label("Update", systemImage: "arrow.down.circle")
                                            Spacer()
                                            Text("v\(info.versionName)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            Section("System Extension") {
                                if systemExtensionInstalled {
                                    FormButton {
                                        Task {
                                            await updateSystemExtension()
                                        }
                                    } label: {
                                        Label("Update", systemImage: "arrow.down.doc.fill")
                                    }
                                    FormButton(role: .destructive) {
                                        Task {
                                            await uninstallSystemExtension()
                                        }
                                    } label: {
                                        Label("Uninstall", systemImage: "trash.fill").foregroundColor(.red)
                                    }
                                } else {
                                    FormButton {
                                        Task {
                                            await installSystemExtension()
                                        }
                                    } label: {
                                        Label("Install", systemImage: "lock.doc.fill")
                                    }
                                }
                            }

                            Section {
                                if !helperStatusLoaded {
                                    ProgressView()
                                } else if rootHelperRegistrationStatus == .enabled {
                                    FormButton {
                                        Task {
                                            do {
                                                try HelperServiceManager.unregisterRootHelper()
                                                try await Task.sleep(for: .seconds(1))
                                                try HelperServiceManager.registerRootHelper()
                                                refreshHelperStatus()
                                            } catch {
                                                alert = AlertState(action: "update helper service", error: error)
                                            }
                                        }
                                    } label: {
                                        Label("Update", systemImage: "arrow.down.doc.fill")
                                    }
                                    FormButton(role: .destructive) {
                                        performHelperAction(actionName: "uninstall helper service") {
                                            try HelperServiceManager.unregisterRootHelper()
                                        }
                                    } label: {
                                        Label("Uninstall", systemImage: "trash.fill").foregroundColor(.red)
                                    }
                                } else if rootHelperRegistrationStatus == .requiresApproval {
                                    FormButton {
                                        openHelperSettings()
                                    } label: {
                                        Label("Enable", systemImage: "switch.2")
                                    }
                                } else {
                                    FormButton {
                                        performHelperAction(actionName: "install helper service") {
                                            try HelperServiceManager.registerRootHelper()
                                        }
                                    } label: {
                                        Label("Install", systemImage: "square.and.arrow.down.fill")
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Helper Service")
                                    Text("This helper service provides process lookup for `process_name` and `process_path` routing rules, and manages the working directory.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                }
                            }
                        }
                    #endif
                }
            }
        }
        .alert($alert)
        #if os(macOS)
            .alert($updateManager.alert)
        #endif
            .navigationTitle("App")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadSettings() async {
        selectedLanguage = Self.currentLanguage()
        #if os(macOS)
            startAtLogin = SMAppService.mainApp.status == .enabled
            menuBarExtraInBackground = await SharedPreferences.menuBarExtraInBackground.get()
            if Variant.useSystemExtension {
                systemExtensionInstalled = await SystemExtension.isInstalled()
                let trackString = await SharedPreferences.updateTrack.get()
                updateTrack = UpdateTrack.resolved(from: trackString)
                checkUpdateEnabled = await SharedPreferences.checkUpdateEnabled.get()
            }
        #endif
        isLoading = false
        #if os(macOS)
            if Variant.useSystemExtension {
                refreshHelperStatus()
                helperStatusLoaded = true
            }
        #endif
        refreshCacheSize()
    }

    private static func currentLanguage() -> String? {
        guard let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = languages.first
        else {
            return nil
        }
        let current = canonicalLanguageCode(first)
        for language in supportedLanguages {
            guard let code = language.code else {
                continue
            }
            if current == code || current.hasPrefix("\(code)-") || current.hasPrefix("\(code)_") {
                return code
            }
        }
        return nil
    }

    private func updateLanguage(_ language: String?) {
        if let language {
            UserDefaults.standard.set([Self.canonicalLanguageCode(language)], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        alert = AlertState(
            title: String(localized: "Restart Required"),
            message: String(localized: "Language will be changed after restarting the app.")
        )
    }

    private static func configuredLanguageCodes() -> [String] {
        let rawCodes: [String]
        if let configured = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String],
           !configured.isEmpty
        {
            rawCodes = configured
        } else if let development = Bundle.main.developmentLocalization, !development.isEmpty {
            rawCodes = [development]
        } else {
            rawCodes = []
        }

        var seen = Set<String>()
        var codes: [String] = []
        for rawCode in rawCodes {
            let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let canonical = canonicalLanguageCode(trimmed)
            guard !canonical.isEmpty, seen.insert(canonical).inserted else {
                continue
            }
            codes.append(canonical)
        }
        return codes
    }

    private static func canonicalLanguageCode(_ code: String) -> String {
        Locale.canonicalLanguageIdentifier(from: code)
    }

    #if os(macOS)

        private func updateLoginItems(_ startAtLogin: Bool) {
            do {
                if startAtLogin {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }

                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                alert = AlertState(action: "update login items", error: error)
            }
        }

        private func installSystemExtension() async {
            do {
                if let result = try await SystemExtension.install() {
                    if result == .willCompleteAfterReboot {
                        alert = AlertState(errorMessage: String(localized: "Need Reboot"))
                        return
                    }
                }
                systemExtensionInstalled = true
            } catch {
                alert = AlertState(action: "install system extension", error: error)
            }
        }

        private func updateSystemExtension() async {
            do {
                if let result = try await SystemExtension.install(forceUpdate: true) {
                    switch result {
                    case .completed:
                        alert = AlertState(
                            title: String(localized: "Update"),
                            message: String(localized: "System Extension updated.")
                        )
                    case .willCompleteAfterReboot:
                        alert = AlertState(
                            title: String(localized: "Update"),
                            message: String(localized: "Reboot required.")
                        )
                    }
                }
            } catch {
                alert = AlertState(action: "update system extension", error: error)
            }
        }

        private func uninstallSystemExtension() async {
            do {
                if let result = try await SystemExtension.uninstall() {
                    switch result {
                    case .completed:
                        systemExtensionInstalled = false
                        alert = AlertState(
                            title: String(localized: "Uninstall"),
                            message: String(localized: "System Extension removed.")
                        )
                    case .willCompleteAfterReboot:
                        alert = AlertState(
                            title: String(localized: "Uninstall"),
                            message: String(localized: "Reboot required.")
                        )
                    }
                }
            } catch {
                alert = AlertState(action: "uninstall system extension", error: error)
            }
        }

        private func performHelperAction(actionName: String, _ action: () throws -> Void) {
            do {
                try action()
                refreshHelperStatus()
            } catch {
                alert = AlertState(action: actionName, error: error)
            }
        }

        private func refreshHelperStatus() {
            rootHelperRegistrationStatus = HelperServiceManager.rootHelperStatus
        }

        private func openHelperSettings() {
            if #available(macOS 13.0, *) {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems"),
               NSWorkspace.shared.open(url)
            {
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }

    #endif

    private func refreshCacheSize() {
        Task.detached {
            let total = Self.calculateDirSize(FilePath.cacheDirectory)
            let working = Self.calculateDirSize(FilePath.workingDirectory)
            let size = max(total - working, 0)
            await MainActor.run {
                cacheSize = size
                cacheSizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        }
    }

    private static func calculateDirSize(_ dir: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}
