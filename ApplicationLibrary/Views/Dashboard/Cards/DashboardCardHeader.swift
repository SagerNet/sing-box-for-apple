import SwiftUI

public struct DashboardCardHeader: View {
    private let icon: String
    private let title: LocalizedStringKey

    public init(icon: String, title: LocalizedStringKey) {
        self.icon = icon
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.primary)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}
