#if !os(tvOS)
    import Library
    import SwiftUI
    import UniformTypeIdentifiers

    #if canImport(AppKit)
        import AppKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    public struct FontPickerView: View {
        private let pool: [String]
        private let onSelect: (String) -> Void

        @State private var selected: String
        @State private var searchText: String = ""
        @Environment(\.dismiss) private var dismiss

        #if os(iOS)
            @StateObject private var fontStore = ImportedFontStore.shared
            @State private var showFileImporter = false
            @State private var alert: AlertState?
            @State private var editMode: EditMode = .inactive
        #endif

        public init(currentName: String, onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
            _selected = State(initialValue: currentName)
            pool = Self.monospacedFamilies()
        }

        public var body: some View {
            List {
                if searchText.isEmpty {
                    Section {
                        familyRow(name: "", label: String(localized: "Follow Theme"))
                    }
                    #if os(iOS)
                        if !fontStore.fonts.isEmpty {
                            Section("Imported") {
                                ForEach(fontStore.fonts) { font in
                                    familyRow(name: font.familyName, label: font.familyName)
                                }
                                .onDelete { offsets in
                                    let targets = offsets.map { fontStore.fonts[$0] }
                                    Task { await deleteImported(targets) }
                                }
                            }
                        }
                    #endif
                    ForEach(groupedKeys, id: \.self) { letter in
                        Section(letter) {
                            ForEach(grouped[letter] ?? [], id: \.self) { family in
                                familyRow(name: family, label: family)
                            }
                        }
                    }
                } else {
                    Section("Fonts") {
                        ForEach(filteredFamilies, id: \.self) { family in
                            familyRow(name: family, label: family)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle("Font")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.editMode, $editMode)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Import from File", systemImage: "doc.badge.plus")
                            }
                            if !fontStore.fonts.isEmpty {
                                Button {
                                    withAnimation {
                                        editMode = editMode.isEditing ? .inactive : .active
                                    }
                                } label: {
                                    Label(
                                        editMode.isEditing ? String(localized: "Done") : String(localized: "Manage Imported Fonts"),
                                        systemImage: "slider.horizontal.3"
                                    )
                                }
                            }
                        } label: {
                            Label("Others", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .alert($alert)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.font],
                    allowsMultipleSelection: true
                ) { result in
                    handleFontImport(result)
                }
            #endif
        }

        private func familyRow(name: String, label: String) -> some View {
            Button {
                select(name)
            } label: {
                HStack {
                    Text(label)
                        .font(name.isEmpty ? .body : .custom(name, size: 17))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected == name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var filteredFamilies: [String] {
            let query = searchText.lowercased()
            #if os(iOS)
                let imported = fontStore.fonts.map(\.familyName)
                let combined = Array(NSOrderedSet(array: imported + pool)) as? [String] ?? pool
                return combined.filter { $0.lowercased().contains(query) }
            #else
                return pool.filter { $0.lowercased().contains(query) }
            #endif
        }

        private var grouped: [String: [String]] {
            #if os(iOS)
                let importedNames = Set(fontStore.fonts.map(\.familyName))
            #endif
            var result: [String: [String]] = [:]
            for family in pool {
                #if os(iOS)
                    if importedNames.contains(family) { continue }
                #endif
                let first = family.first.map(String.init)?.uppercased() ?? "#"
                let key = first.first?.isLetter == true ? first : "#"
                result[key, default: []].append(family)
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

        #if os(iOS)
            private func handleFontImport(_ result: Result<[URL], Error>) {
                do {
                    let urls = try result.get()
                    guard !urls.isEmpty else { return }
                    Task {
                        for url in urls {
                            do {
                                try await fontStore.importFile(from: url)
                            } catch {
                                alert = AlertState(action: "import font", error: error)
                                return
                            }
                        }
                    }
                } catch {
                    alert = AlertState(action: "import font", error: error)
                }
            }

            private func deleteImported(_ targets: [ImportedFont]) async {
                for font in targets {
                    do {
                        try await fontStore.delete(font)
                        if selected == font.familyName {
                            selected = ""
                        }
                    } catch {
                        alert = AlertState(action: "remove font", error: error)
                        return
                    }
                }
                if fontStore.fonts.isEmpty, editMode.isEditing {
                    withAnimation { editMode = .inactive }
                }
            }
        #endif

        private static func monospacedFamilies() -> [String] {
            #if canImport(AppKit)
                let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
                var families = Set<String>()
                for name in names {
                    let family = NSFont(name: name, size: 12)?.familyName ?? name
                    families.insert(family)
                }
                return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            #elseif canImport(UIKit)
                return UIFont.familyNames.filter { family in
                    UIFont.fontNames(forFamilyName: family).contains { name in
                        guard let font = UIFont(name: name, size: 12) else { return false }
                        return font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
                    }
                }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            #else
                return []
            #endif
        }
    }
#endif
