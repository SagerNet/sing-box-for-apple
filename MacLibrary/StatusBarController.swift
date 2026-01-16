import AppKit
import Combine
import Foundation
import Libbox
import Library

@MainActor
public class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusItemView: StatusBarItemView?
    private var menuIcon: NSImage?
    private var isIconOnlyMode = true
    private let environments: ExtensionEnvironments
    private var commandClient: CommandClient?
    private var cancellables = Set<AnyCancellable>()
    private var statusCancellable: AnyCancellable?
    private var speedMode: MenuBarExtraSpeedMode = .enabled

    private var menu: NSMenu?
    private var headerItem: NSMenuItem?
    private var headerView: StatusBarHeaderView?
    private var urlTestAllItem: NSMenuItem?
    private var urlTestAllView: StatusBarURLTestView?
    private var urlTestGroupViews: [String: StatusBarURLTestView] = [:]
    private var groupMenuItems: [String: NSMenuItem] = [:]
    private var groupOutboundItems: [String: [String: NSMenuItem]] = [:]
    private var groupOrder: [String] = []
    private var outboundOrderByGroup: [String: [String]] = [:]
    private var groupsItem: NSMenuItem?
    private var profilesItem: NSMenuItem?
    private var currentGroups: [LibboxOutboundGroup] = []
    private var isURLTestingAll = false
    private var urlTestingGroups = Set<String>()

    public init(environments: ExtensionEnvironments) {
        self.environments = environments
        super.init()
        observeProfile()
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        let showMenuBarExtra = await SharedPreferences.showMenuBarExtra.get()
        speedMode = await MenuBarExtraSpeedMode(rawValue: SharedPreferences.menuBarExtraSpeedMode.get()) ?? .enabled
        updateVisibility(showMenuBarExtra)
    }

    public func updateVisibility(_ show: Bool) {
        if show {
            createStatusItem()
        } else {
            destroyStatusItem()
        }
    }

    public func updateSpeedMode(_ mode: Int) {
        speedMode = MenuBarExtraSpeedMode(rawValue: mode) ?? .enabled
        updateCommandClient()
    }

    private func createStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let button = statusItem!.button!
        if let image = NSImage(named: "MenuIcon") {
            image.isTemplate = true
            menuIcon = image
            button.image = image
        }
        isIconOnlyMode = true

        menu = NSMenu()
        menu!.delegate = self
        statusItem!.menu = menu

        buildMenu()
        updateCommandClient()
    }

    private func destroyStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        statusItemView = nil
        menu = nil
        headerView = nil
        urlTestAllView = nil
        urlTestAllItem = nil
        urlTestGroupViews.removeAll()
        groupMenuItems.removeAll()
        groupOutboundItems.removeAll()
        groupOrder.removeAll()
        outboundOrderByGroup.removeAll()
        currentGroups = []
        isURLTestingAll = false
        urlTestingGroups.removeAll()
        commandClient?.disconnect()
        commandClient = nil
    }

    private func buildMenu() {
        guard let menu else { return }
        menu.removeAllItems()

        headerView = StatusBarHeaderView(environments: environments)
        headerItem = NSMenuItem()
        headerItem!.view = headerView
        menu.addItem(headerItem!)

        groupsItem = NSMenuItem(title: NSLocalizedString("Group", comment: ""), action: nil, keyEquivalent: "")
        groupsItem!.submenu = NSMenu()
        groupsItem!.isHidden = true
        menu.addItem(groupsItem!)

        profilesItem = NSMenuItem(title: NSLocalizedString("Profile", comment: ""), action: nil, keyEquivalent: "")
        profilesItem!.submenu = NSMenu()
        menu.addItem(profilesItem!)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: NSLocalizedString("Open", comment: ""), action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: NSLocalizedString("Quit", comment: ""), action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        Task {
            await loadProfiles()
        }
    }

    private func observeProfile() {
        environments.$extensionProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.headerView?.updateProfile(profile)
                self?.observeProfileStatus(profile)
                self?.updateCommandClient()
                self?.updateGroupsVisibility()
            }
            .store(in: &cancellables)

        environments.profileUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadProfiles()
                }
            }
            .store(in: &cancellables)

        environments.selectedProfileUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadProfiles()
                }
            }
            .store(in: &cancellables)

        environments.commandClient.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] groups in
                self?.updateGroupsMenu(groups)
            }
            .store(in: &cancellables)
    }

    private func observeProfileStatus(_ profile: ExtensionProfile?) {
        statusCancellable = nil
        guard let profile else { return }
        statusCancellable = profile.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCommandClient()
                self?.updateGroupsVisibility()
            }
    }

    private func updateGroupsVisibility() {
        let isConnected = environments.extensionProfile?.status.isConnected == true
        groupsItem?.isHidden = !isConnected
        if isConnected {
            environments.commandClient.connect()
        }
        updateURLTestAvailability()
    }

    private func loadProfiles() async {
        guard let submenu = profilesItem?.submenu else { return }
        submenu.removeAllItems()

        let profileList: [ProfilePreview]
        do {
            profileList = try await ProfileManager.list().map { ProfilePreview($0) }
        } catch {
            return
        }

        if profileList.isEmpty {
            let emptyItem = NSMenuItem(title: NSLocalizedString("Empty profiles", comment: ""), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        var selectedProfileID = await SharedPreferences.selectedProfileID.get()
        if !profileList.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profileList[0].id
            await SharedPreferences.selectedProfileID.set(selectedProfileID)
        }

        for profile in profileList {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == selectedProfileID ? .on : .off
            submenu.addItem(item)
        }
    }

    private func updateGroupsMenu(_ groups: [LibboxOutboundGroup]?) {
        currentGroups = groups ?? []
        guard let submenu = groupsItem?.submenu else { return }

        let groups = currentGroups

        let selectableGroups = groups.filter(\.selectable)
        if selectableGroups.isEmpty {
            groupsItem?.isHidden = true
            updateURLTestAvailability()
            return
        }

        groupsItem?.isHidden = environments.extensionProfile?.status.isConnected != true

        let newGroupOrder = selectableGroups.map(\.tag)
        var newOutboundOrderByGroup: [String: [String]] = [:]
        for group in selectableGroups {
            var tags: [String] = []
            let items = group.getItems()!
            while items.hasNext() {
                tags.append(items.next()!.tag)
            }
            newOutboundOrderByGroup[group.tag] = tags
        }

        let structureSame = newGroupOrder == groupOrder
            && newOutboundOrderByGroup == outboundOrderByGroup
            && urlTestAllView != nil
            && !groupMenuItems.isEmpty

        if structureSame {
            if !updateGroupMenuItems(selectableGroups) {
                rebuildGroupsMenu(selectableGroups, submenu: submenu)
                groupOrder = newGroupOrder
                outboundOrderByGroup = newOutboundOrderByGroup
            }
        } else {
            rebuildGroupsMenu(selectableGroups, submenu: submenu)
            groupOrder = newGroupOrder
            outboundOrderByGroup = newOutboundOrderByGroup
        }

        updateURLTestAvailability()
    }

    private func rebuildGroupsMenu(_ selectableGroups: [LibboxOutboundGroup], submenu: NSMenu) {
        submenu.removeAllItems()
        urlTestGroupViews.removeAll()
        groupMenuItems.removeAll()
        groupOutboundItems.removeAll()

        let urlTestAllView = StatusBarURLTestView(title: NSLocalizedString("URLTest", comment: "")) { [weak self] in
            self?.performURLTestForAllGroups()
        }
        let urlTestAllItem = NSMenuItem()
        urlTestAllItem.view = urlTestAllView
        self.urlTestAllView = urlTestAllView
        self.urlTestAllItem = urlTestAllItem
        submenu.addItem(urlTestAllItem)

        let closeAllItem = NSMenuItem(
            title: NSLocalizedString("Close All Connections", comment: ""),
            action: #selector(closeAllConnections),
            keyEquivalent: ""
        )
        closeAllItem.target = self
        submenu.addItem(closeAllItem)

        submenu.addItem(NSMenuItem.separator())

        let font = NSFont.menuFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        for group in selectableGroups {
            let groupItem = NSMenuItem(title: group.tag, action: nil, keyEquivalent: "")
            let groupSubmenu = NSMenu()

            let groupURLTestView = StatusBarURLTestView(title: NSLocalizedString("URLTest", comment: "")) { [weak self] in
                self?.performURLTestForGroup(group.tag)
            }
            let groupURLTestItem = NSMenuItem()
            groupURLTestItem.view = groupURLTestView
            groupSubmenu.addItem(groupURLTestItem)
            groupSubmenu.addItem(NSMenuItem.separator())
            urlTestGroupViews[group.tag] = groupURLTestView

            var outboundItemsByTag: [String: NSMenuItem] = [:]
            var outboundData: [(LibboxOutboundGroupItem, NSMenuItem)] = []
            var maxTagWidth: CGFloat = 0
            var maxDelayWidth: CGFloat = 0

            let items = group.getItems()!
            while items.hasNext() {
                let outbound = items.next()!
                let outboundItem = NSMenuItem(
                    title: outbound.tag,
                    action: #selector(selectOutbound(_:)),
                    keyEquivalent: ""
                )
                outboundItem.target = self
                outboundItem.representedObject = ["groupTag": group.tag, "outboundTag": outbound.tag]
                outboundItem.state = group.selected == outbound.tag ? .on : .off
                outboundItemsByTag[outbound.tag] = outboundItem

                let tagWidth = (outbound.tag as NSString).size(withAttributes: attrs).width
                maxTagWidth = max(maxTagWidth, tagWidth)

                if outbound.urlTestDelay > 0 {
                    let delayText = "\(outbound.urlTestDelay)ms"
                    let delayWidth = (delayText as NSString).size(withAttributes: attrs).width
                    maxDelayWidth = max(maxDelayWidth, delayWidth)
                }

                outboundData.append((outbound, outboundItem))
            }

            let tabLocation = maxTagWidth + 20 + maxDelayWidth
            let tabStop = NSTextTab(textAlignment: .right, location: tabLocation)
            let style = NSMutableParagraphStyle()
            style.tabStops = [tabStop]

            for (outbound, outboundItem) in outboundData {
                let delay = outbound.urlTestDelay
                let delayText = delay > 0 ? "\(delay)ms" : ""
                let fullText = "\(outbound.tag)\t\(delayText)"
                let attrString = NSMutableAttributedString(
                    string: fullText,
                    attributes: [.font: font, .paragraphStyle: style]
                )
                if delay > 0 {
                    let color = NSColor.delayColor(for: UInt16(delay))
                    let delayStart = (fullText as NSString).length - (delayText as NSString).length
                    attrString.addAttribute(
                        .foregroundColor,
                        value: color,
                        range: NSRange(location: delayStart, length: (delayText as NSString).length)
                    )
                }
                outboundItem.attributedTitle = attrString
                groupSubmenu.addItem(outboundItem)
            }

            groupItem.submenu = groupSubmenu
            submenu.addItem(groupItem)
            groupMenuItems[group.tag] = groupItem
            groupOutboundItems[group.tag] = outboundItemsByTag
        }
    }

    private func updateGroupMenuItems(_ selectableGroups: [LibboxOutboundGroup]) -> Bool {
        let font = NSFont.menuFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        for group in selectableGroups {
            guard let outboundItemsByTag = groupOutboundItems[group.tag] else { return false }

            var outboundData: [(LibboxOutboundGroupItem, NSMenuItem)] = []
            var maxTagWidth: CGFloat = 0
            var maxDelayWidth: CGFloat = 0

            let items = group.getItems()!
            while items.hasNext() {
                let outbound = items.next()!
                guard let outboundItem = outboundItemsByTag[outbound.tag] else { return false }
                outboundItem.state = group.selected == outbound.tag ? .on : .off

                let tagWidth = (outbound.tag as NSString).size(withAttributes: attrs).width
                maxTagWidth = max(maxTagWidth, tagWidth)

                if outbound.urlTestDelay > 0 {
                    let delayText = "\(outbound.urlTestDelay)ms"
                    let delayWidth = (delayText as NSString).size(withAttributes: attrs).width
                    maxDelayWidth = max(maxDelayWidth, delayWidth)
                }

                outboundData.append((outbound, outboundItem))
            }

            let tabLocation = maxTagWidth + 20 + maxDelayWidth
            let tabStop = NSTextTab(textAlignment: .right, location: tabLocation)
            let style = NSMutableParagraphStyle()
            style.tabStops = [tabStop]

            for (outbound, outboundItem) in outboundData {
                let delay = outbound.urlTestDelay
                let delayText = delay > 0 ? "\(delay)ms" : ""
                let fullText = "\(outbound.tag)\t\(delayText)"
                let attrString = NSMutableAttributedString(
                    string: fullText,
                    attributes: [.font: font, .paragraphStyle: style]
                )
                if delay > 0 {
                    let color = NSColor.delayColor(for: UInt16(delay))
                    let delayStart = (fullText as NSString).length - (delayText as NSString).length
                    attrString.addAttribute(
                        .foregroundColor,
                        value: color,
                        range: NSRange(location: delayStart, length: (delayText as NSString).length)
                    )
                }
                outboundItem.attributedTitle = attrString
            }
        }

        return true
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? Int64 else { return }
        Task {
            await SharedPreferences.selectedProfileID.set(profileID)
            environments.selectedProfileUpdate.send()
            if environments.extensionProfile?.status.isConnected == true {
                do {
                    try await environments.extensionProfile?.reloadService()
                } catch {
                    showAlert(error: error)
                }
            }
            await loadProfiles()
        }
    }

    @objc private func selectOutbound(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let groupTag = info["groupTag"],
              let outboundTag = info["outboundTag"]
        else { return }

        Task {
            do {
                try await LibboxNewStandaloneCommandClient()!.selectOutbound(groupTag, outboundTag: outboundTag)
            } catch {
                showAlert(error: error)
            }
        }
    }

    @objc private func closeAllConnections() {
        do {
            try LibboxNewStandaloneCommandClient()!.closeConnections()
        } catch {
            showAlert(error: error)
        }
    }

    @objc private func openApp() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            dockApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateCommandClient() {
        guard statusItem != nil else { return }
        let shouldConnect = speedMode != .disabled && environments.extensionProfile?.status.isConnectedStrict == true
        if shouldConnect {
            if commandClient == nil {
                commandClient = CommandClient(.status)
                commandClient!.statusPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        self?.updateSpeedDisplay(status: status)
                    }
                    .store(in: &cancellables)
            }
            commandClient!.connect()
        } else {
            commandClient?.disconnect()
            updateSpeedDisplay(status: nil)
        }
    }

    private func updateSpeedDisplay(status: LibboxStatusMessage?) {
        guard let statusItem, let button = statusItem.button else { return }
        let title: String
        if speedMode == .disabled || status == nil || !status!.trafficAvailable {
            title = ""
        } else if speedMode == .enabled {
            title = "\(LibboxFormatBytes(status!.uplink))/s\n\(LibboxFormatBytes(status!.downlink))/s"
        } else {
            title = "\(LibboxFormatBytes(status!.uplink + status!.downlink))/s"
        }

        let shouldUseIconOnly = title.isEmpty
        if shouldUseIconOnly != isIconOnlyMode {
            isIconOnlyMode = shouldUseIconOnly
            if shouldUseIconOnly {
                statusItemView?.removeFromSuperview()
                statusItemView = nil
                button.image = menuIcon
                statusItem.length = NSStatusItem.squareLength
            } else {
                button.image = nil
                let itemView = StatusBarItemView()
                itemView.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(itemView)
                NSLayoutConstraint.activate([
                    itemView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    itemView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                    itemView.topAnchor.constraint(equalTo: button.topAnchor),
                    itemView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                ])
                statusItemView = itemView
                itemView.attach(to: button)
                itemView.setIcon(menuIcon!)
                itemView.setTitle(title)
                updateStatusItemLength()
            }
        } else if !shouldUseIconOnly {
            statusItemView?.setTitle(title)
            updateStatusItemLength()
        }
    }

    private func updateStatusItemLength() {
        guard let statusItem, let statusItemView else { return }
        let width = statusItemView.fittingWidth()
        statusItem.length = max(width, NSStatusBar.system.thickness)
    }

    private func showAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Error", comment: "")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
        alert.runModal()
    }

    private func updateURLTestAvailability() {
        let isConnected = environments.extensionProfile?.status.isConnected == true
        let hasGroups = currentGroups.contains(where: \.selectable)
        let isAnyGroupTesting = !urlTestingGroups.isEmpty
        let allEnabled = isConnected && hasGroups && !isURLTestingAll && !isAnyGroupTesting
        urlTestAllView?.setLoading(isURLTestingAll)
        urlTestAllView?.setEnabled(allEnabled)
        urlTestAllItem?.isHidden = !isConnected || !hasGroups

        for (tag, view) in urlTestGroupViews {
            let isGroupTesting = urlTestingGroups.contains(tag)
            view.setLoading(isGroupTesting)
            view.setEnabled(isConnected && !isURLTestingAll && !isGroupTesting)
        }
    }

    private func performURLTestForAllGroups() {
        let groups = currentGroups.filter(\.selectable)
        guard !groups.isEmpty else { return }
        guard environments.extensionProfile?.status.isConnected == true else { return }
        guard !isURLTestingAll else { return }
        setURLTestAllRunning(true)

        Task {
            do {
                let client = LibboxNewStandaloneCommandClient()!
                for group in groups {
                    try await client.urlTest(group.tag)
                }
            } catch {
                await showAlert(error: error)
            }
            await MainActor.run {
                self.setURLTestAllRunning(false)
            }
        }
    }

    private func performURLTestForGroup(_ tag: String) {
        guard environments.extensionProfile?.status.isConnected == true else { return }
        guard !isURLTestingAll else { return }
        guard !urlTestingGroups.contains(tag) else { return }
        setURLTestGroupRunning(tag, true)

        Task {
            do {
                let client = LibboxNewStandaloneCommandClient()!
                try await client.urlTest(tag)
            } catch {
                await showAlert(error: error)
            }
            await MainActor.run {
                self.setURLTestGroupRunning(tag, false)
            }
        }
    }

    private func setURLTestAllRunning(_ running: Bool) {
        isURLTestingAll = running
        updateURLTestAvailability()
    }

    private func setURLTestGroupRunning(_ tag: String, _ running: Bool) {
        if running {
            urlTestingGroups.insert(tag)
        } else {
            urlTestingGroups.remove(tag)
        }
        updateURLTestAvailability()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_: NSMenu) {
        headerView?.refresh()
        statusItemView?.setHighlighted(true)
        Task {
            await loadProfiles()
        }
    }

    public func menuDidClose(_: NSMenu) {
        statusItemView?.setHighlighted(false)
    }
}

// MARK: - StatusBarItemView

@MainActor
private class StatusBarItemView: NSView {
    private enum Layout {
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 2
        static let spacing: CGFloat = 6
        static let lineHeight: CGFloat = 9
        static let fontSize: CGFloat = 8.75
        static let textWidth: CGFloat = 42
    }

    private let imageView: NSImageView
    private let textField: NSTextField
    private let stackView: NSStackView
    private let textAttributes: [NSAttributedString.Key: Any]
    private var currentTitle = ""
    private var isHighlighted = false
    private weak var statusButton: NSStatusBarButton?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var textWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        imageView = NSImageView()
        textField = NSTextField(labelWithString: "")
        stackView = NSStackView()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = Layout.lineHeight
        paragraphStyle.minimumLineHeight = Layout.lineHeight
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byClipping
        textAttributes = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: Layout.fontSize),
            .foregroundColor: NSColor.labelColor,
        ]

        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        textField.isEditable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isHidden = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 2
        textField.usesSingleLineMode = false
        textField.alignment = .right
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.distribution = .equalSpacing
        stackView.alignment = .centerY
        stackView.spacing = Layout.spacing
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(textField)
        addSubview(stackView)

        leadingConstraint = stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding)
        trailingConstraint = stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalPadding)
        topConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalPadding)
        bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalPadding)
        textWidthConstraint = textField.widthAnchor.constraint(equalToConstant: Layout.textWidth)

        NSLayoutConstraint.activate([
            leadingConstraint!,
            trailingConstraint!,
            topConstraint!,
            bottomConstraint!,
            textWidthConstraint!,
        ])
    }

    func setIcon(_ image: NSImage) {
        imageView.image = image
        imageView.isHidden = false
        updateTintColor()
    }

    func setTitle(_ title: String) {
        guard !title.isEmpty else { return }
        currentTitle = title
        updateTitle()
    }

    func attach(to button: NSStatusBarButton) {
        statusButton = button
        updateHighlight(button.isHighlighted)
    }

    func setHighlighted(_ highlighted: Bool) {
        updateHighlight(highlighted)
    }

    func fittingWidth() -> CGFloat {
        layoutSubtreeIfNeeded()
        let width = stackView.fittingSize.width + Layout.horizontalPadding * 2
        return ceil(width)
    }

    private func updateTitle() {
        guard !currentTitle.isEmpty else { return }
        var attributes = textAttributes
        attributes[.foregroundColor] = isHighlighted
            ? NSColor.unemphasizedSelectedTextColor
            : NSColor.labelColor
        textField.attributedStringValue = NSAttributedString(string: currentTitle, attributes: attributes)
        textField.isHidden = false
    }

    private func updateTintColor() {
        imageView.contentTintColor = isHighlighted
            ? NSColor.unemphasizedSelectedTextColor
            : NSColor.labelColor
    }

    private func updateHighlight(_ highlighted: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted
        statusButton?.highlight(isHighlighted)
        updateTitle()
        updateTintColor()
        needsDisplay = true
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        updateHighlight(statusButton?.isHighlighted == true)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - StatusBarURLTestView

@MainActor
private class StatusBarURLTestView: NSView {
    private let titleLabel: NSTextField
    private let progressIndicator: NSProgressIndicator
    private let action: () -> Void
    private var isEnabled = true
    private var isLoading = false
    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        titleLabel = NSTextField(labelWithString: title)
        progressIndicator = NSProgressIndicator()
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 22))
        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: progressIndicator.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateState()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        updateState()
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        updateState()
    }

    private func updateState() {
        let canInteract = isEnabled && !isLoading
        if !canInteract {
            isHighlighted = false
        }
        if isHighlighted, canInteract {
            titleLabel.textColor = NSColor.selectedMenuItemTextColor
        } else {
            titleLabel.textColor = canInteract ? NSColor.labelColor : NSColor.disabledControlTextColor
        }
        if isLoading {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled, !isLoading else { return }
        isHighlighted = true
        titleLabel.textColor = NSColor.selectedMenuItemTextColor
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard isEnabled, !isLoading else { return }
        isHighlighted = false
        titleLabel.textColor = NSColor.labelColor
        needsDisplay = true
    }

    override func mouseDown(with _: NSEvent) {
        guard isEnabled, !isLoading else { return }
        isHighlighted = true
        titleLabel.textColor = NSColor.selectedMenuItemTextColor
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, !isLoading else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            action()
        }
        isHighlighted = false
        titleLabel.textColor = NSColor.labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedMenuItemColor.setFill()
            dirtyRect.fill()
        } else {
            NSColor.clear.setFill()
            dirtyRect.fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - StatusBarHeaderView

@MainActor
private class StatusBarHeaderView: NSView {
    private let environments: ExtensionEnvironments
    private let titleLabel: NSTextField
    private let statusSwitch: NSSwitch
    private let loadingIndicator: NSProgressIndicator
    private var cancellables = Set<AnyCancellable>()

    init(environments: ExtensionEnvironments) {
        self.environments = environments

        titleLabel = NSTextField(labelWithString: "sing-box")
        statusSwitch = NSSwitch()
        loadingIndicator = NSProgressIndicator()

        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 36))
        setupView()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        statusSwitch.target = self
        statusSwitch.action = #selector(statusSwitchChanged)
        statusSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusSwitch)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimation(nil)
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            statusSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func refresh() {
        Task {
            if environments.extensionProfile == nil {
                await environments.reload()
            }
            updateProfile(environments.extensionProfile)
        }
    }

    func updateProfile(_ profile: ExtensionProfile?) {
        loadingIndicator.isHidden = profile != nil
        statusSwitch.isHidden = profile == nil

        if let profile {
            statusSwitch.isEnabled = profile.status.isEnabled
            statusSwitch.state = profile.status.isConnected ? .on : .off
            observeProfileStatus(profile)
        }
    }

    private func observeProfileStatus(_ profile: ExtensionProfile) {
        cancellables.removeAll()
        profile.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.statusSwitch.isEnabled = status.isEnabled
                self?.statusSwitch.state = status.isConnected ? .on : .off
            }
            .store(in: &cancellables)
    }

    @objc private func statusSwitchChanged() {
        let isOn = statusSwitch.state == .on
        Task {
            do {
                if isOn {
                    try await environments.extensionProfile?.start()
                } else {
                    try await environments.extensionProfile?.stop()
                }
            } catch {
                statusSwitch.state = isOn ? .off : .on
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Error", comment: "")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
                alert.runModal()
            }
        }
    }
}

// MARK: - NSColor Extension

extension NSColor {
    static func delayColor(for delay: UInt16) -> NSColor {
        switch delay {
        case 0:
            return .systemGray
        case ..<800:
            return .systemGreen
        case 800 ..< 1500:
            return .systemYellow
        default:
            return .systemOrange
        }
    }
}
