import Library
import SwiftUI

public struct ProfileCard: View {
    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64

    public init(
        profileList: Binding<[ProfilePreview]>,
        selectedProfileID: Binding<Int64>
    ) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
    }

    public var body: some View {
        DashboardCardView(title: "Profile", isHalfWidth: false) {
            VStack(alignment: .leading, spacing: 12) {
                #if os(iOS) || os(tvOS)
                    Picker("", selection: $selectedProfileID) {
                        ForEach(profileList, id: \.id) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                #elseif os(macOS)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(profileList, id: \.id) { profile in
                            HStack {
                                Button {
                                    selectedProfileID = profile.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: selectedProfileID == profile.id ? "circle.fill" : "circle")
                                            .font(.system(size: 12))
                                        Text(profile.name)
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(selectedProfileID == profile.id ? .accentColor : .primary)
                            }
                        }
                    }
                #endif
            }
        }
    }
}
