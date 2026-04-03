import SwiftUI

private struct OrderedStringMap {
    let entries: [(key: String, value: String)]

    init?(data: Data) {
        guard let json = String(data: data, encoding: .utf8) else { return nil }
        var entries: [(key: String, value: String)] = []
        var rest = json[...]

        func skip(_ ch: Character) -> Bool {
            rest = rest.drop(while: \.isWhitespace)
            guard rest.first == ch else { return false }
            rest = rest.dropFirst()
            return true
        }

        func readString() -> String? {
            rest = rest.drop(while: \.isWhitespace)
            guard rest.first == "\"" else { return nil }
            rest = rest.dropFirst()
            var s = ""
            while let ch = rest.first, ch != "\"" {
                if ch == "\\" { rest = rest.dropFirst() }
                if let c = rest.first { s.append(c); rest = rest.dropFirst() }
            }
            if !rest.isEmpty { rest = rest.dropFirst() }
            return s
        }

        guard skip("{") else { return nil }
        while true {
            guard let key = readString(), skip(":"), let value = readString() else { break }
            if !value.isEmpty { entries.append((key: key, value: value)) }
            if !skip(",") { break }
        }
        self.entries = entries
    }
}

@MainActor
public struct MetadataFormView: View {
    @State private var entries: [(key: String, value: String)] = []
    @State private var isLoading = true

    let url: URL
    let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    public var body: some View {
        FormView {
            if !isLoading {
                Section {
                    ForEach(entries, id: \.key) { entry in
                        FormTextItem(LocalizedStringKey(entry.key), entry.value)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if entries.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            Task.detached {
                let loaded = loadEntries()
                await MainActor.run {
                    entries = loaded
                    isLoading = false
                }
            }
        }
        .navigationTitle(title)
    }

    private nonisolated func loadEntries() -> [(key: String, value: String)] {
        guard let data = try? Data(contentsOf: url),
              let map = OrderedStringMap(data: data)
        else {
            return []
        }
        return map.entries
    }
}
