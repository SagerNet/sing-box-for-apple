import Library
import SwiftUI

@MainActor public struct CardManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var configuration = DashboardCardConfiguration()

    public init() {}

    public var body: some View {
        #if os(macOS)
            macOSBody
        #else
            iOSBody
        #endif
    }

    #if os(macOS)
        private var macOSBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Dashboard Items")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Group {
                    if configuration.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        listContent
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset", role: .destructive) {
                        Task {
                            await configuration.resetToDefault()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
    #else
        private var iOSBody: some View {
            NavigationStackCompat {
                Group {
                    if configuration.isLoading {
                        ProgressView()
                    } else {
                        listContent
                    }
                }
                .navigationTitle("Dashboard Items")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Reset", role: .destructive) {
                                Task {
                                    await configuration.resetToDefault()
                                }
                            }
                        }
                    }
            }
        }
    #endif

    private var listContent: some View {
        List {
            ForEach(configuration.cardOrder) { card in
                CardRow(
                    card: card,
                    isEnabled: configuration.isEnabled(card),
                    onToggle: {
                        configuration.toggleCard(card)
                    }
                )
            }
            .onMove { source, destination in
                Task {
                    await configuration.moveCard(from: source, to: destination)
                }
            }
        }
        .applyContentMargins()
    }
}

#if os(tvOS)
    @MainActor public struct CardManagementView: View {
        @StateObject private var configuration = DashboardCardConfiguration()
        @FocusState private var focusedCard: DashboardCard?
        @State private var movingCard: DashboardCard?
        private let onDisappear: (() -> Void)?

        public init(onDisappear: (() -> Void)? = nil) {
            self.onDisappear = onDisappear
        }

        public var body: some View {
            Group {
                if configuration.isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(configuration.cardOrder) { card in
                                TVCardRow(
                                    card: card,
                                    isEnabled: configuration.isEnabled(card),
                                    isMoving: movingCard == card,
                                    focusedCard: $focusedCard,
                                    onToggle: {
                                        configuration.toggleCard(card)
                                    },
                                    onToggleMoving: {
                                        withAnimation {
                                            if movingCard == card {
                                                movingCard = nil
                                            } else {
                                                movingCard = card
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                    .focusSection()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TVToolbarButton(title: "Reset") {
                        Task {
                            await configuration.resetToDefault()
                        }
                    }
                }
            }
            .onMoveCommand { direction in
                guard let movingCard,
                      let currentIndex = configuration.cardOrder.firstIndex(of: movingCard)
                else { return }

                let newIndex: Int
                switch direction {
                case .up:
                    guard currentIndex > 0 else { return }
                    newIndex = currentIndex - 1
                case .down:
                    guard currentIndex < configuration.cardOrder.count - 1 else { return }
                    newIndex = currentIndex + 1
                default:
                    return
                }

                Task {
                    await configuration.moveCard(from: IndexSet(integer: currentIndex), to: newIndex > currentIndex ? newIndex + 1 : newIndex)
                }
                focusedCard = movingCard
            }
            .onDisappear {
                onDisappear?()
            }
        }
    }

    private struct TVCardRow: View {
        let card: DashboardCard
        let isEnabled: Bool
        let isMoving: Bool
        var focusedCard: FocusState<DashboardCard?>.Binding
        let onToggle: () -> Void
        let onToggleMoving: () -> Void

        private var isProfileCard: Bool {
            card == .profile
        }

        var body: some View {
            HStack(spacing: 16) {
                Label(card.title, systemImage: card.systemImage)
                    .font(.headline)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer()

                if !isProfileCard {
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { _ in onToggle() }
                    ))
                    .labelsHidden()
                }

                Button {
                    onToggleMoving()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .actionButtonStyle()
                .focused(focusedCard, equals: card)
            }
            .padding()
            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(isMoving ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isMoving)
        }
    }
#endif

private struct CardRow: View {
    let card: DashboardCard
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .imageScale(.small)

            Toggle(isOn: isToggleEnabled) {
                Label(card.title, systemImage: card.systemImage)
            }
            .disabled(isProfileCard)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
    }

    private var isToggleEnabled: Binding<Bool> {
        Binding(
            get: { isProfileCard || isEnabled },
            set: { _ in if !isProfileCard { onToggle() } }
        )
    }

    private var isProfileCard: Bool {
        card == .profile
    }
}

private extension View {
    @ViewBuilder
    func applyContentMargins() -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            contentMargins(.top, 0, for: .scrollContent)
        } else {
            self
        }
    }
}
