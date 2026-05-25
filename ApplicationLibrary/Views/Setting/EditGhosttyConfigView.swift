import Library
import SwiftUI
import UniformTypeIdentifiers

public struct EditGhosttyConfigView: View {
    public enum Scheme {
        case light
        case dark

        var configPreference: SharedPreferences.Preference<String> {
            switch self {
            case .light: SharedPreferences.tailscaleSSHGhosttyLightConfig
            case .dark: SharedPreferences.tailscaleSSHGhosttyDarkConfig
            }
        }

        var navigationTitle: String {
            switch self {
            case .light: String(localized: "Light Custom Configuration")
            case .dark: String(localized: "Dark Custom Configuration")
            }
        }
    }

    private let scheme: Scheme

    @State private var isLoading = true
    @State private var content: String = ""
    @State private var saveTask: Task<Void, Never>?

    #if !os(tvOS)
        @State private var showFileImporter = false
        @State private var alert: AlertState?
    #endif

    @Environment(\.ghosttyConfigEditor) private var ghosttyConfigEditor

    public init(scheme: Scheme) {
        self.scheme = scheme
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView().onAppear {
                    Task {
                        await load()
                    }
                }
            } else {
                editor
                    .onChangeCompat(of: content) { newValue in
                        scheduleSave(newValue)
                    }
            }
        }
        #if !os(tvOS)
        .onDrop(of: [.data], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        #endif
        .navigationTitle(scheme.navigationTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .toolbar {
            Menu {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import from File", systemImage: "doc.badge.plus")
                }
            } label: {
                Label("Others", systemImage: "line.3.horizontal.circle")
            }
        }
        .alert($alert)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        #endif
    }

    @ViewBuilder
    private var editor: some View {
        if let ghosttyConfigEditor {
            ghosttyConfigEditor($content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            defaultEditor
        }
    }

    @ViewBuilder
    private var defaultEditor: some View {
        #if os(tvOS)
            ScrollView {
                TextField(text: $content, axis: .vertical) {}
                    .lineLimit(1000)
                    .font(Font.system(.caption2, design: .monospaced))
                    .autocorrectionDisabled(true)
            }
        #else
            TextEditor(text: $content)
                .font(Font.system(.caption2, design: .monospaced))
                .autocorrectionDisabled(true)
            #if os(macOS)
                .textContentType(.init(rawValue: ""))
                .padding()
            #endif
        #endif
    }

    private func load() async {
        content = await scheme.configPreference.get()
        isLoading = false
    }

    private func scheduleSave(_ newValue: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await scheme.configPreference.set(newValue)
        }
    }

    #if !os(tvOS)
        private func handleFileImport(_ result: Result<[URL], Error>) {
            do {
                if let url = try result.get().first {
                    importContent(from: url)
                }
            } catch {
                alert = AlertState(action: "import ghostty configuration", error: error)
            }
        }

        private func importContent(from url: URL) {
            Task { @MainActor in
                do {
                    let data = try await BlockingIO.run {
                        try url.withRequiredSecurityScopedAccess(
                            or: NSError(domain: "EditGhosttyConfigView", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Missing access to selected file")])
                        ) {
                            try Data(contentsOf: url)
                        }
                    }
                    try applyImportedData(data)
                } catch {
                    alert = AlertState(action: "import ghostty configuration", error: error)
                }
            }
        }

        @MainActor
        private func applyImportedData(_ data: Data) throws {
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "EditGhosttyConfigView", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "File is not valid UTF-8 text")])
            }
            content = text
        }

        private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
            guard let provider = providers.first else { return false }
            let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .data) ?? false
            }) ?? provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                Task { @MainActor in
                    do {
                        guard let data else {
                            throw error ?? NSError(domain: "EditGhosttyConfigView", code: 0, userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to read dropped file")])
                        }
                        try applyImportedData(data)
                    } catch {
                        alert = AlertState(action: "import ghostty configuration", error: error)
                    }
                }
            }
            return true
        }
    #endif
}
