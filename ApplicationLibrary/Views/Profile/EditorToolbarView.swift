import SwiftUI

#if os(iOS) || os(macOS)

    public struct EditorToolbarView: View {
        let canUndo: Bool
        let canRedo: Bool
        let onUndo: () -> Void
        let onRedo: () -> Void
        let onFormat: () -> Void
        let onInsertSymbol: (String) -> Void
        let configurationError: String?
        let onDismissError: () -> Void

        public init(
            canUndo: Bool,
            canRedo: Bool,
            onUndo: @escaping () -> Void,
            onRedo: @escaping () -> Void,
            onFormat: @escaping () -> Void,
            onInsertSymbol: @escaping (String) -> Void,
            configurationError: String?,
            onDismissError: @escaping () -> Void
        ) {
            self.canUndo = canUndo
            self.canRedo = canRedo
            self.onUndo = onUndo
            self.onRedo = onRedo
            self.onFormat = onFormat
            self.onInsertSymbol = onInsertSymbol
            self.configurationError = configurationError
            self.onDismissError = onDismissError
        }

        public var body: some View {
            VStack(spacing: 2) {
                if let error = configurationError {
                    errorBanner(error)
                }
                symbolBar
            }
        }

        private func errorBanner(_ error: String) -> some View {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.footnote)
                    .lineLimit(2)
                Spacer()
                Button {
                    onDismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #if os(iOS)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            #else
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            #endif
                .padding(.horizontal, 8)
        }

        private var symbolBar: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    actionButtons
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    symbolButtons
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            #if os(iOS)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            #else
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            #endif
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }

        private var actionButtons: some View {
            HStack(spacing: 4) {
                Button {
                    onUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)

                Button {
                    onRedo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!canRedo)

                Button {
                    onFormat()
                } label: {
                    Label("Format", systemImage: "text.alignleft")
                }
            }
            .buttonStyle(.bordered)
        }

        private var symbolButtons: some View {
            HStack(spacing: 2) {
                ForEach(primarySymbols, id: \.self) { symbol in
                    symbolButton(symbol)
                }
                ForEach(secondarySymbols, id: \.self) { symbol in
                    symbolButton(symbol)
                }
            }
            .buttonStyle(.bordered)
        }

        private var primarySymbols: [String] {
            ["\"", ":", ",", "{", "}", "[", "]"]
        }

        private var secondarySymbols: [String] {
            ["true", "false"]
        }

        private func symbolButton(_ symbol: String) -> some View {
            Button {
                onInsertSymbol(symbol)
            } label: {
                Text(symbol)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                #if os(iOS)
                    .frame(minWidth: symbol.count > 1 ? nil : 32, minHeight: 32)
                #else
                    .frame(minWidth: symbol.count > 1 ? nil : 24)
                #endif
            }
        }
    }

#endif
