import Library
import SwiftUI

@MainActor public struct CardManagementSheet: View {
    @StateObject private var configuration = DashboardCardConfiguration()
    @Binding private var configurationVersion: Int

    public init(configurationVersion: Binding<Int>) {
        _configurationVersion = configurationVersion
    }

    public var body: some View {
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
                    #if os(iOS) || os(tvOS)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Reset", role: .destructive) {
                                Task {
                                    await configuration.resetToDefault()
                                    configurationVersion += 1
                                }
                            }
                        }
                    #else
                        ToolbarItem(placement: .automatic) {
                            Button("Reset", role: .destructive) {
                                Task {
                                    await configuration.resetToDefault()
                                    configurationVersion += 1
                                }
                            }
                        }
                    #endif
                }
        }
    }

    private var listContent: some View {
        List {
            ForEach(configuration.cardOrder) { card in
                CardRow(
                    card: card,
                    isEnabled: configuration.isEnabled(card),
                    onToggle: {
                        configuration.toggleCard(card)
                        configurationVersion += 1
                    }
                )
            }
            .onMove { source, destination in
                configuration.moveCard(from: source, to: destination)
                configurationVersion += 1
            }
        }
        .applyContentMargins()
    }
}

private struct CardRow: View {
    let card: DashboardCard
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .imageScale(.small)

            if isProfileCard {
                Label(card.title, systemImage: card.systemImage)
                Spacer()
                Text("Required")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Toggle(isOn: isToggleEnabled) {
                    Label(card.title, systemImage: card.systemImage)
                }
                .opacity(isEnabled ? 1.0 : 0.5)
            }
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
