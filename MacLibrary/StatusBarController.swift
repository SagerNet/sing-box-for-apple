import AppKit
import Combine
import CoreText
import Foundation
import Libbox
import Library

@MainActor
public class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menuIcon: NSImage?
    private var isIconOnlyMode = true
    private let environments: ExtensionEnvironments
    private var commandClient: CommandClient?
    private var cancellables = Set<AnyCancellable>()
    private var statusCancellable: AnyCancellable?
    private var speedMode: MenuBarExtraSpeedMode = .enabled
    private var statusItemTitle: String?
    private var statusItemIsHighlighted = false
    private var statusItemTextModeSize: NSSize?

    private enum StatusItemLayout {
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 2
        static let spacing: CGFloat = 6
        static let lineHeight: CGFloat = 9
        static let fontSize: CGFloat = 8.75
        static let textWidth: CGFloat = 42
        static let unifiedLineHeight: CGFloat = 11
        static let unifiedFontSize: CGFloat = 10.5
    }

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
        button.title = ""
        button.imagePosition = .imageOnly
        if let image = NSImage(named: "MenuIcon") {
            image.isTemplate = true
            menuIcon = image
        }
        button.image = renderStatusItemIconOnlyImage(highlighted: statusItemIsHighlighted)
        statusItem!.length = statusItemIconOnlyImageSize().width
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
        statusItemTitle = nil
        statusItemIsHighlighted = false
        statusItemTextModeSize = nil
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
                statusItemTitle = nil
                statusItemTextModeSize = nil
                button.image = renderStatusItemIconOnlyImage(highlighted: statusItemIsHighlighted)
                statusItem.length = statusItemIconOnlyImageSize().width
            } else {
                statusItemTitle = title
                let image = renderStatusItemImage(
                    title: title,
                    highlighted: statusItemIsHighlighted,
                    unified: speedMode == .unified
                )
                button.image = image
                if let image {
                    statusItemTextModeSize = image.size
                    statusItem.length = max(image.size.width, NSStatusBar.system.thickness)
                }
            }
        } else if !shouldUseIconOnly {
            if title != statusItemTitle {
                statusItemTitle = title
                button.image = renderStatusItemImage(
                    title: title,
                    highlighted: statusItemIsHighlighted,
                    unified: speedMode == .unified
                )
            }
        }
    }

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard statusItemIsHighlighted != highlighted else { return }
        statusItemIsHighlighted = highlighted
        guard let button = statusItem?.button else { return }
        if isIconOnlyMode {
            button.image = renderStatusItemIconOnlyImage(highlighted: highlighted)
            return
        }
        guard let title = statusItemTitle else { return }
        button.image = renderStatusItemImage(
            title: title,
            highlighted: highlighted,
            unified: speedMode == .unified
        )
    }

    private func renderStatusItemIconOnlyImage(highlighted: Bool) -> NSImage? {
        guard let icon = menuIcon else { return nil }
        let size = statusItemIconOnlyImageSize()
        let iconSize = statusItemIconSize(forHeight: size.height)
        guard iconSize.width > 0, iconSize.height > 0 else { return nil }
        let iconColor = highlighted ? NSColor.unemphasizedSelectedTextColor : NSColor.labelColor

        let image = NSImage(size: size, flipped: false) { _ in
            let iconRect = NSRect(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            NSGraphicsContext.saveGraphicsState()
            iconColor.setFill()
            iconRect.fill()
            icon.draw(
                in: iconRect,
                from: .zero,
                operation: .destinationIn,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func renderStatusItemImage(title: String, highlighted: Bool, unified: Bool) -> NSImage? {
        let size = statusItemTextModeSize ?? statusItemImageSize()
        let textColor = highlighted ? NSColor.unemphasizedSelectedTextColor : NSColor.labelColor
        let iconColor = textColor
        let icon = menuIcon
        let iconSize = statusItemIconSize(forHeight: size.height)
        let lineHeight = unified ? StatusItemLayout.unifiedLineHeight : StatusItemLayout.lineHeight
        let fontSize = unified ? StatusItemLayout.unifiedFontSize : StatusItemLayout.fontSize
        let textX = StatusItemLayout.horizontalPadding + iconSize.width + (iconSize.width > 0 ? StatusItemLayout.spacing : 0)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let textRect: NSRect
        if unified {
            textRect = NSRect(x: textX, y: 0, width: StatusItemLayout.textWidth, height: size.height)
        } else {
            let textBounds = attributedTitle.boundingRect(
                with: NSSize(width: StatusItemLayout.textWidth, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let textHeight = min(ceil(textBounds.height), size.height)
            let textY = (size.height - textHeight) / 2
            textRect = NSRect(x: textX, y: textY, width: StatusItemLayout.textWidth, height: textHeight)
        }

        let image = NSImage(size: size, flipped: false) { _ in
            if let icon, iconSize.width > 0 {
                let iconY = (size.height - iconSize.height) / 2
                let iconRect = NSRect(
                    x: StatusItemLayout.horizontalPadding,
                    y: iconY,
                    width: iconSize.width,
                    height: iconSize.height
                )
                NSGraphicsContext.saveGraphicsState()
                iconColor.setFill()
                iconRect.fill()
                icon.draw(
                    in: iconRect,
                    from: .zero,
                    operation: .destinationIn,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                NSGraphicsContext.restoreGraphicsState()
            }

            if unified, let context = NSGraphicsContext.current?.cgContext {
                let line = CTLineCreateWithAttributedString(attributedTitle)
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                let textHeight = ascent + descent
                let baselineY = (size.height - textHeight) / 2 + descent
                context.saveGState()
                context.textPosition = CGPoint(x: textRect.minX, y: baselineY)
                CTLineDraw(line, context)
                context.restoreGState()
            } else {
                attributedTitle.draw(
                    with: textRect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    context: nil
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func statusItemImageSize() -> NSSize {
        let height = NSStatusBar.system.thickness
        let iconSize = statusItemIconSize(forHeight: height)
        let spacing = iconSize.width > 0 ? StatusItemLayout.spacing : 0
        let width = StatusItemLayout.horizontalPadding * 2 + iconSize.width + spacing + StatusItemLayout.textWidth
        let size = NSSize(width: ceil(width), height: ceil(height))
        statusItemTextModeSize = size
        return size
    }

    private func statusItemIconOnlyImageSize() -> NSSize {
        let height = NSStatusBar.system.thickness
        let iconSize = statusItemIconSize(forHeight: height)
        let contentWidth = StatusItemLayout.horizontalPadding * 2 + iconSize.width
        let width = max(ceil(contentWidth), NSStatusBar.system.thickness)
        return NSSize(width: width, height: ceil(height))
    }

    private func statusItemIconSize(forHeight height: CGFloat) -> NSSize {
        guard let menuIcon else { return .zero }
        let maxIconHeight = height - StatusItemLayout.verticalPadding * 2
        guard maxIconHeight > 0 else { return .zero }
        let scale = min(1, maxIconHeight / menuIcon.size.height)
        return NSSize(width: menuIcon.size.width * scale, height: menuIcon.size.height * scale)
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
        setStatusItemHighlighted(true)
        Task {
            await loadProfiles()
        }
    }

    public func menuDidClose(_: NSMenu) {
        setStatusItemHighlighted(false)
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
