#if !os(tvOS)
    import Library
    import SwiftUI

    public struct GhosttyConfigurationView: View {
        private static let lightDefaultTheme = "Alabaster"
        private static let darkDefaultTheme = "Afterglow"

        @State private var isLoading = true
        @State private var lightPickerTheme: String = lightDefaultTheme
        @State private var lightCustomEnabled: Bool = false
        @State private var darkPickerTheme: String = darkDefaultTheme
        @State private var darkCustomEnabled: Bool = false
        @State private var fontFollowTheme: Bool = true
        @State private var fontFamily: String = ""
        @State private var fontSize: Double = 0

        public init() {}

        public var body: some View {
            FormView {
                if !isLoading {
                    schemeSection(
                        header: "Light Configuration",
                        isDark: false,
                        pickerTheme: $lightPickerTheme,
                        customEnabled: $lightCustomEnabled,
                        themePreference: SharedPreferences.tailscaleSSHGhosttyLightTheme
                    )
                    schemeSection(
                        header: "Dark Configuration",
                        isDark: true,
                        pickerTheme: $darkPickerTheme,
                        customEnabled: $darkCustomEnabled,
                        themePreference: SharedPreferences.tailscaleSSHGhosttyDarkTheme
                    )
                    fontSection()
                }
            }
            .navigationTitle("Ghostty Configuration")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .onAppear {
                    reload()
                }
        }

        private func fontSection() -> some View {
            Section(header: Text("Font Configuration")) {
                Toggle("Follow Theme", isOn: $fontFollowTheme)
                    .onChangeCompat(of: fontFollowTheme) { newValue in
                        Task {
                            await SharedPreferences.tailscaleSSHTerminalFontFollowTheme.set(newValue)
                        }
                    }
                if !fontFollowTheme {
                    FormNavigationLink {
                        FontPickerView(currentName: fontFamily) { newName in
                            Task {
                                await SharedPreferences.tailscaleSSHTerminalFontFamily.set(newName)
                                fontFamily = newName
                            }
                        }
                    } label: {
                        HStack {
                            Text("Font")
                            Spacer()
                            Text(fontFamily.isEmpty ? String(localized: "Follow Theme") : fontFamily)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $fontSize, in: 8 ... 32, step: 1) {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChangeCompat(of: fontSize) { newValue in
                        Task {
                            await SharedPreferences.tailscaleSSHTerminalFontSize.set(newValue)
                        }
                    }
                }
            }
        }

        private func schemeSection(
            header: LocalizedStringKey,
            isDark: Bool,
            pickerTheme: Binding<String>,
            customEnabled: Binding<Bool>,
            themePreference: SharedPreferences.Preference<String>
        ) -> some View {
            Section(header: Text(header)) {
                themeRow(isDark: isDark, pickerTheme: pickerTheme, themePreference: themePreference)
                    .disabled(customEnabled.wrappedValue)
                Toggle("Custom Configuration", isOn: customEnabled)
                    .onChangeCompat(of: customEnabled.wrappedValue) { newValue in
                        Task {
                            await themePreference.set(newValue ? "" : pickerTheme.wrappedValue)
                        }
                    }
                if customEnabled.wrappedValue {
                    FormNavigationLink {
                        EditGhosttyConfigView(scheme: isDark ? .dark : .light)
                    } label: {
                        Text("Edit Custom Configuration")
                    }
                }
            }
        }

        @ViewBuilder
        private func themeRow(
            isDark: Bool,
            pickerTheme: Binding<String>,
            themePreference: SharedPreferences.Preference<String>
        ) -> some View {
            if let pickerMaker = TailscaleSSHLaunchService.shared.ghosttyThemePickerMaker {
                FormNavigationLink {
                    pickerMaker(isDark, pickerTheme.wrappedValue) { newName in
                        guard !newName.isEmpty else { return }
                        Task {
                            await themePreference.set(newName)
                            pickerTheme.wrappedValue = newName
                        }
                    }
                } label: {
                    themeRowLabel(value: pickerTheme.wrappedValue)
                }
            } else {
                themeRowLabel(value: pickerTheme.wrappedValue)
            }
        }

        private func themeRowLabel(value: String) -> some View {
            HStack {
                Text("Theme")
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }

        private func reload() {
            let lightStored = SharedPreferences.tailscaleSSHGhosttyLightTheme.getBlocking()
            if lightStored.isEmpty {
                lightCustomEnabled = true
                lightPickerTheme = Self.lightDefaultTheme
            } else {
                lightCustomEnabled = false
                lightPickerTheme = lightStored
            }
            let darkStored = SharedPreferences.tailscaleSSHGhosttyDarkTheme.getBlocking()
            if darkStored.isEmpty {
                darkCustomEnabled = true
                darkPickerTheme = Self.darkDefaultTheme
            } else {
                darkCustomEnabled = false
                darkPickerTheme = darkStored
            }
            fontFollowTheme = SharedPreferences.tailscaleSSHTerminalFontFollowTheme.getBlocking()
            fontFamily = SharedPreferences.tailscaleSSHTerminalFontFamily.getBlocking()
            fontSize = SharedPreferences.tailscaleSSHTerminalFontSize.getBlocking()
            isLoading = false
        }
    }
#endif
