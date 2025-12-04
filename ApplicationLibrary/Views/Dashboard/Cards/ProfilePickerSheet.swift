import Library
import QRCode
import SwiftUI
#if canImport(AppKit)
    import AppKit
#endif

@MainActor
struct ProfilePickerSheet: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @Environment(\.dismiss) private var dismiss

    @Binding var profileList: [ProfilePreview]
    @Binding var selectedProfileID: Int64

    #if !os(macOS)
        @State private var editMode: EditMode = .inactive
    #else
        @State private var isEditing = false
        @State private var rowWidth: CGFloat = 400
    #endif
    @State private var profileToEdit: Profile?
    @State private var alert: AlertState?
    #if os(tvOS)
        @FocusState private var focusedProfileID: Int64?
        @State private var movingProfileID: Int64?
    #endif

    private var isEditingActive: Bool {
        #if !os(macOS)
            editMode.isEditing
        #else
            isEditing
        #endif
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                iOSBody
                    .environment(\.editMode, $editMode)
            } else {
                legacyIOSBody
                    .environment(\.editMode, $editMode)
            }
        #else
            nonIOSBody
        #endif
    }

    #if os(iOS)
        @available(iOS 26, *)
        private var iOSBody: some View {
            listContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
                .sheet(item: $profileToEdit) { profile in
                    NavigationSheet(title: "Edit Profile") {
                        EditProfileView()
                            .environmentObject(profile)
                            .environmentObject(environments)
                    }
                }
                .alert($alert)
        }

        private var legacyIOSBody: some View {
            legacyListContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                }
                .sheet(item: $profileToEdit) { profile in
                    NavigationSheet(title: "Edit Profile") {
                        EditProfileView()
                            .environmentObject(profile)
                            .environmentObject(environments)
                    }
                }
                .alert($alert)
        }
    #endif

    #if !os(iOS)
        private var nonIOSBody: some View {
            listContent
            #if os(tvOS)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    TVToolbarButton(title: editMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            if editMode.isEditing {
                                movingProfileID = nil
                            }
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                }
            }
            .navigationDestination(item: $profileToEdit) { profile in
                EditProfileView()
                    .environmentObject(profile)
                    .environmentObject(environments)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            BackButton()
                        }
                    }
            }
            #elseif os(macOS)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        if isEditing {
                            Button("Done") {
                                withAnimation {
                                    isEditing = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Edit") {
                                withAnimation {
                                    isEditing = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .sheet(item: $profileToEdit) { profile in
                NavigationSheet {
                    EditProfileView()
                        .environmentObject(profile)
                        .environmentObject(environments)
                }
                .frame(minWidth: 500, minHeight: 400)
            }
            #endif
            .alert($alert)
        }
    #endif

    private var listContent: some View {
        #if os(tvOS)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(profileList, id: \.id) { profile in
                        ProfilePickerRow(
                            profile: profile,
                            isSelected: profile.id == selectedProfileID,
                            isMoving: movingProfileID == profile.id,
                            alert: $alert,
                            focusedProfileID: $focusedProfileID,
                            onSelect: {
                                selectedProfileID = profile.id
                                dismiss()
                            },
                            onEdit: {
                                profileToEdit = profile.origin
                            },
                            onUpdate: {
                                await updateProfile(profile)
                            },
                            onDelete: {
                                if let index = profileList.firstIndex(where: { $0.id == profile.id }) {
                                    deleteProfile(at: IndexSet(integer: index))
                                }
                            },
                            onToggleMoving: {
                                withAnimation {
                                    if movingProfileID == profile.id {
                                        movingProfileID = nil
                                    } else {
                                        movingProfileID = profile.id
                                    }
                                }
                            }
                        )
                        .environmentObject(environments)
                    }
                }
                .padding()
            }
            .onAppear {
                focusedProfileID = selectedProfileID
            }
            .onMoveCommand { direction in
                guard let movingID = movingProfileID,
                      let currentIndex = profileList.firstIndex(where: { $0.id == movingID })
                else { return }

                let newIndex: Int
                switch direction {
                case .up:
                    guard currentIndex > 0 else { return }
                    newIndex = currentIndex - 1
                case .down:
                    guard currentIndex < profileList.count - 1 else { return }
                    newIndex = currentIndex + 1
                default:
                    return
                }

                withAnimation {
                    moveProfile(from: IndexSet(integer: currentIndex), to: newIndex > currentIndex ? newIndex + 1 : newIndex)
                }
                focusedProfileID = movingID
            }
        #elseif os(macOS)
            List {
                ForEach(profileList, id: \.id) { profile in
                    macOSProfileRow(profile)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                }
            }
            .listStyle(.plain)
        #else
            List {
                ForEach(profileList, id: \.id) { profile in
                    ProfilePickerRow(
                        profile: profile,
                        isSelected: profile.id == selectedProfileID,
                        alert: $alert,
                        onSelect: {
                            selectedProfileID = profile.id
                            dismiss()
                        },
                        onEdit: {
                            profileToEdit = profile.origin
                        },
                        onUpdate: {
                            await updateProfile(profile)
                        }
                    )
                    .environmentObject(environments)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }
                .onMove(perform: moveProfile)
                .onDelete(perform: deleteProfile)
            }
            .listStyle(.plain)
        #endif
    }

    #if os(iOS)
        @ViewBuilder
        private var legacyListContent: some View {
            if editMode.isEditing {
                legacyEditingList
            } else {
                legacyNormalList
            }
        }

        private var legacyEditingList: some View {
            List {
                ForEach(profileList, id: \.id) { profile in
                    LegacyProfilePickerRow(
                        profile: profile,
                        isSelected: profile.id == selectedProfileID,
                        alert: $alert,
                        onSelect: {
                            selectedProfileID = profile.id
                            dismiss()
                        },
                        onEdit: {
                            profileToEdit = profile.origin
                        },
                        onUpdate: {
                            await updateProfile(profile)
                        }
                    )
                    .environmentObject(environments)
                }
                .onMove(perform: legacyMoveProfile)
                .onDelete(perform: legacyDeleteProfile)
            }
        }

        private var legacyNormalList: some View {
            List {
                ForEach(profileList, id: \.id) { profile in
                    LegacyProfilePickerRow(
                        profile: profile,
                        isSelected: profile.id == selectedProfileID,
                        alert: $alert,
                        onSelect: {
                            selectedProfileID = profile.id
                            dismiss()
                        },
                        onEdit: {
                            profileToEdit = profile.origin
                        },
                        onUpdate: {
                            await updateProfile(profile)
                        }
                    )
                    .environmentObject(environments)
                }
            }
        }

        private func legacyMoveProfile(from source: IndexSet, to destination: Int) {
            profileList.move(fromOffsets: source, toOffset: destination)
            for (index, profile) in profileList.enumerated() {
                profileList[index].order = UInt32(index)
                profile.origin.order = UInt32(index)
            }
            Task {
                do {
                    try await ProfileManager.update(profileList.map(\.origin))
                    environments.profileUpdate.send()
                } catch {
                    // Handle error silently
                }
            }
        }

        private func legacyDeleteProfile(at offsets: IndexSet) {
            let profilesToDelete = offsets.map { profileList[$0].origin }
            profileList.remove(atOffsets: offsets)
            Task {
                do {
                    _ = try await ProfileManager.delete(profilesToDelete)
                    environments.emptyProfiles = profileList.isEmpty
                    environments.profileUpdate.send()
                } catch {
                    // Handle error silently
                }
            }
        }
    #endif

    private func updateProfile(_ profile: ProfilePreview) async {
        do {
            try await profile.origin.updateRemoteProfile()
            environments.profileUpdate.send()
        } catch {
            alert = AlertState(
                title: String(localized: "Update Failed"),
                message: error.localizedDescription
            )
        }
    }

    private func moveProfile(from source: IndexSet, to destination: Int) {
        profileList.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in profileList.enumerated() {
            profileList[index].order = UInt32(index)
            profile.origin.order = UInt32(index)
        }
        Task {
            do {
                try await ProfileManager.update(profileList.map(\.origin))
                environments.profileUpdate.send()
            } catch {
                // Handle error silently
            }
        }
    }

    private func deleteProfile(at offsets: IndexSet) {
        let profilesToDelete = offsets.map { profileList[$0].origin }
        profileList.remove(atOffsets: offsets)
        Task {
            do {
                _ = try await ProfileManager.delete(profilesToDelete)
                environments.emptyProfiles = profileList.isEmpty
                environments.profileUpdate.send()
            } catch {
                // Handle error silently
            }
        }
    }

    #if os(macOS)
        @ViewBuilder
        private func macOSProfileRow(_ profile: ProfilePreview) -> some View {
            ProfilePickerRow(
                profile: profile,
                isSelected: profile.id == selectedProfileID,
                isEditing: isEditingActive,
                alert: $alert,
                onSelect: {
                    selectedProfileID = profile.id
                    dismiss()
                },
                onEdit: {
                    profileToEdit = profile.origin
                },
                onUpdate: {
                    await updateProfile(profile)
                },
                onDelete: {
                    if let index = profileList.firstIndex(where: { $0.id == profile.id }) {
                        deleteProfile(at: IndexSet(integer: index))
                    }
                }
            )
            .environmentObject(environments)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: RowWidthKey.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(RowWidthKey.self) { rowWidth = $0 }
            .draggable(String(profile.id)) {
                ProfilePickerRow.previewContent(profile: profile, width: rowWidth)
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, targetID: profile.id)
            }
        }

        private func handleDrop(items: [String], targetID: Int64) -> Bool {
            guard let draggedIDString = items.first,
                  let draggedID = Int64(draggedIDString),
                  let fromIndex = profileList.firstIndex(where: { $0.id == draggedID }),
                  let toIndex = profileList.firstIndex(where: { $0.id == targetID }),
                  fromIndex != toIndex
            else {
                return false
            }
            moveProfile(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
            return true
        }
    #endif
}

// MARK: - ProfilePickerRow

private struct ProfilePickerRow: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    #if !os(macOS)
        @Environment(\.editMode) private var editMode
    #endif

    let profile: ProfilePreview
    let isSelected: Bool
    #if os(macOS)
        let isEditing: Bool
    #endif
    #if os(tvOS)
        let isMoving: Bool
    #endif
    @Binding var alert: AlertState?
    #if os(tvOS)
        var focusedProfileID: FocusState<Int64?>.Binding
    #endif
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onUpdate: () async -> Void
    #if os(tvOS) || os(macOS)
        let onDelete: () -> Void
    #endif
    #if os(tvOS)
        let onToggleMoving: () -> Void
    #endif

    #if !os(macOS)
        private var isEditing: Bool {
            editMode?.wrappedValue.isEditing ?? false
        }
    #endif

    @State private var isUpdating = false
    @State private var showQRCode = false
    #if os(macOS)
        @State private var shareItemType: ShareItemType?
        @State private var menuAnchorView: NSView?
    #endif

    var body: some View {
        #if os(tvOS)
            tvOSBody
        #else
            defaultBody
        #endif
    }

    #if os(tvOS)
        private var tvOSBody: some View {
            Group {
                if isEditing {
                    tvOSEditingBody
                } else {
                    tvOSNormalBody
                }
            }
            .sheet(isPresented: $showQRCode) {
                if let remoteURL = profile.remoteURL {
                    QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                }
            }
        }

        private var tvOSNormalBody: some View {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.tint)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        profileInfo
                    }

                    Spacer()

                    Color.clear.frame(width: 70)
                }
                .padding()
            }
            .buttonStyle(.card)
            .focused(focusedProfileID, equals: profile.id)
            .disabled(isUpdating)
            .overlay(alignment: .trailing) {
                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if profile.type == .remote {
                        Button {
                            isUpdating = true
                            Task {
                                await onUpdate()
                                isUpdating = false
                            }
                        } label: {
                            Label("Update", systemImage: "arrow.clockwise")
                        }

                        Menu {
                            Button {
                                showQRCode = true
                            } label: {
                                Label("Share URL as QR Code", systemImage: "qrcode")
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .actionButtonStyle()
                .disabled(isUpdating)
                .padding(.trailing, 12)
            }
        }

        private var tvOSEditingBody: some View {
            HStack(spacing: 12) {
                Color.clear.frame(width: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    profileInfo
                }

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .actionButtonStyle()

                Button {
                    onToggleMoving()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .actionButtonStyle()
                .focused(focusedProfileID, equals: profile.id)
            }
            .padding()
            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(isMoving ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isMoving)
        }
    #endif

    #if !os(tvOS)
        @ViewBuilder
        private var defaultBody: some View {
            #if os(macOS)
                if isEditing {
                    macOSEditingBody
                } else {
                    macOSNormalBody
                }
            #else
                iOSBody
            #endif
        }

        #if os(macOS)
            private var macOSNormalBody: some View {
                Button {
                    if !isUpdating {
                        onSelect()
                    }
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .sheet(isPresented: $showQRCode) {
                    if let remoteURL = profile.remoteURL {
                        QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                    }
                }
            }

            private var macOSEditingBody: some View {
                rowContent
            }
        #endif

        #if os(iOS)
            private var iOSBody: some View {
                Button {
                    if !isEditing, !isUpdating {
                        onSelect()
                    }
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(isEditing || isUpdating)
                .sheet(isPresented: $showQRCode) {
                    if let remoteURL = profile.remoteURL {
                        QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                    }
                }
            }
        #endif

        private var rowContent: some View {
            HStack(spacing: 12) {
                #if os(macOS)
                    Group {
                        if isEditing {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.tint)
                                .opacity(isSelected ? 1 : 0)
                        }
                    }
                    .frame(width: 16)
                #else
                    if !isEditing {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tint)
                            .opacity(isSelected ? 1 : 0)
                    }
                #endif

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    profileInfo
                }

                Spacer()

                #if os(macOS)
                    if isEditing {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } else {
                        rowMenu
                    }
                #else
                    if !isEditing {
                        rowMenu
                    }
                #endif
            }
            .contentShape(Rectangle())
            .padding(16)
            .cardStyle()
        }
    #endif

    private var rowMenu: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if profile.type == .remote {
                Button {
                    isUpdating = true
                    Task {
                        await onUpdate()
                        isUpdating = false
                    }
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                }
            }

            #if !os(tvOS)
                shareMenu
            #endif
        } label: {
            Group {
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .background(ViewAnchor { menuAnchorView = $0 })
            .onChange(of: shareItemType) { shareItemType in
                guard let shareItemType else { return }
                self.shareItemType = nil
                shareProfile(type: shareItemType)
            }
        #endif
    }

    #if !os(tvOS)
        @ViewBuilder
        private var shareMenu: some View {
            Menu {
                #if os(macOS)
                    Button {
                        shareItemType = .file
                    } label: {
                        Label("Share File", systemImage: "doc")
                    }
                #else
                    ShareButtonCompat($alert) {
                        Label("Share File", systemImage: "doc")
                    } itemURL: {
                        try profile.origin.toContent().generateShareFile()
                    }
                #endif

                if profile.type == .remote {
                    Button {
                        showQRCode = true
                    } label: {
                        Label("Share URL as QR Code", systemImage: "qrcode")
                    }
                }

                #if os(macOS)
                    Button {
                        shareItemType = .json
                    } label: {
                        Label("Share Content JSON File", systemImage: "curlybraces")
                    }
                #else
                    ShareButtonCompat($alert) {
                        Label("Share Content JSON File", systemImage: "curlybraces")
                    } itemURL: {
                        try profile.origin.read().generateShareFile(name: "\(profile.name).json")
                    }
                #endif
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    #endif

    private var profileInfo: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: profile.type == .remote ? "cloud.fill" : "doc.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(profile.type == .remote ? "Remote" : "Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if profile.type == .remote, let lastUpdated = profile.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(lastUpdated.myFormat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    #if os(macOS)
        private func shareProfile(type: ShareItemType) {
            do {
                let url: URL
                switch type {
                case .file:
                    url = try profile.origin.toContent().generateShareFile()
                case .json:
                    url = try profile.origin.read().generateShareFile(name: "\(profile.name).json")
                }
                let anchorView = menuAnchorView ?? NSApp.keyWindow?.contentView ?? NSView()
                NSSharingServicePicker(items: [url]).show(
                    relativeTo: .zero,
                    of: anchorView,
                    preferredEdge: .minY
                )
            } catch {
                alert = AlertState(error: error)
            }
        }

        static func previewContent(profile: ProfilePreview, width: CGFloat) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.body)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: profile.type == .remote ? "cloud.fill" : "doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(profile.type == .remote ? "Remote" : "Local")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if profile.type == .remote, let lastUpdated = profile.lastUpdated {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(lastUpdated.myFormat)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
            .frame(width: width)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    #endif
}

// MARK: - macOS Helpers

#if os(macOS)
    private struct RowWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 400
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private enum ShareItemType {
        case file
        case json
    }

    private struct ViewAnchor: NSViewRepresentable {
        let callback: (NSView) -> Void

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async {
                callback(view)
            }
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }
#endif

// MARK: - Legacy iOS ProfilePickerRow (iOS < 26)

#if os(iOS)
    private struct LegacyProfilePickerRow: View {
        @EnvironmentObject private var environments: ExtensionEnvironments
        @Environment(\.editMode) private var editMode

        let profile: ProfilePreview
        let isSelected: Bool
        @Binding var alert: AlertState?
        let onSelect: () -> Void
        let onEdit: () -> Void
        let onUpdate: () async -> Void

        private var isEditing: Bool {
            editMode?.wrappedValue.isEditing ?? false
        }

        @State private var isUpdating = false
        @State private var showQRCode = false

        var body: some View {
            Group {
                if isEditing {
                    editingBody
                } else {
                    normalBody
                }
            }
            .transaction { $0.animation = nil }
        }

        private var editingBody: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    profileInfo
                }
                Spacer()
            }
        }

        private var normalBody: some View {
            HStack(spacing: 12) {
                Button {
                    if !isUpdating {
                        onSelect()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tint)
                            .opacity(isSelected ? 1 : 0)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            profileInfo
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)

                Spacer()

                rowMenu
            }
            .sheet(isPresented: $showQRCode) {
                if let remoteURL = profile.remoteURL {
                    QRCodeSheet(profileName: profile.name, remoteURL: remoteURL)
                }
            }
        }

        private var rowMenu: some View {
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                if profile.type == .remote {
                    Button {
                        isUpdating = true
                        Task {
                            await onUpdate()
                            isUpdating = false
                        }
                    } label: {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                }

                shareMenu
            } label: {
                Group {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private var shareMenu: some View {
            Menu {
                ShareButtonCompat($alert) {
                    Label("Share File", systemImage: "doc")
                } itemURL: {
                    try profile.origin.toContent().generateShareFile()
                }

                if profile.type == .remote {
                    Button {
                        showQRCode = true
                    } label: {
                        Label("Share URL as QR Code", systemImage: "qrcode")
                    }
                }

                ShareButtonCompat($alert) {
                    Label("Share Content JSON File", systemImage: "curlybraces")
                } itemURL: {
                    try profile.origin.read().generateShareFile(name: "\(profile.name).json")
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        private var profileInfo: some View {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: profile.type == .remote ? "cloud.fill" : "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(profile.type == .remote ? "Remote" : "Local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if profile.type == .remote, let lastUpdated = profile.lastUpdated {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(lastUpdated.myFormat)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
#endif
