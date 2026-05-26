#if canImport(GhosttyTerminal)
    import GhosttyTheme
    import SwiftUI

    public struct ThemePickerView: View {
        public enum Scheme: Sendable {
            case light
            case dark

            var navigationTitle: String {
                switch self {
                case .light: NSLocalizedString("Light Theme", comment: "")
                case .dark: NSLocalizedString("Dark Theme", comment: "")
                }
            }

            var isDark: Bool {
                self == .dark
            }
        }

        private let scheme: Scheme
        private let pool: [GhosttyThemeDefinition]
        private let onSelect: (String) -> Void

        @State private var selected: String
        @State private var searchText: String = ""
        @Environment(\.dismiss) private var dismiss

        public init(scheme: Scheme, currentName: String, onSelect: @escaping (String) -> Void) {
            self.scheme = scheme
            self.onSelect = onSelect
            _selected = State(initialValue: currentName)
            pool = GhosttyThemeCatalog.allThemes
                .filter { scheme.isDark ? $0.isDark : !$0.isDark }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        public var body: some View {
            List {
                if searchText.isEmpty {
                    ForEach(groupedKeys, id: \.self) { letter in
                        Section(letter) {
                            ForEach(grouped[letter] ?? []) { theme in
                                themeRow(theme)
                            }
                        }
                    }
                } else {
                    Section("Themes") {
                        ForEach(filteredThemes) { theme in
                            themeRow(theme)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(scheme.navigationTitle)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }

        private func themeRow(_ theme: GhosttyThemeDefinition) -> some View {
            Button {
                select(theme.name)
            } label: {
                HStack {
                    Text(theme.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected == theme.name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var filteredThemes: [GhosttyThemeDefinition] {
            let query = searchText.lowercased()
            return pool.filter { $0.name.lowercased().contains(query) }
        }

        private var grouped: [String: [GhosttyThemeDefinition]] {
            var result: [String: [GhosttyThemeDefinition]] = [:]
            for theme in pool {
                let first = theme.name.first.map(String.init)?.uppercased() ?? "#"
                let key = first.first?.isLetter == true ? first : "#"
                result[key, default: []].append(theme)
            }
            return result
        }

        private var groupedKeys: [String] {
            grouped.keys.sorted()
        }

        private func select(_ name: String) {
            selected = name
            onSelect(name)
            dismiss()
        }
    }
#endif
