import AppKit

@MainActor
final class CompletionPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private static let rowHeight: CGFloat = 22
    private static let maxVisibleRows = 10
    private static let contentPadding: CGFloat = 4

    private let panel: NSPanel
    private let tableView: NSTableView
    private let scrollView: NSScrollView

    private var items = [CompletionItem]()
    var onAccept: ((CompletionItem) -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let effectView = NSVisualEffectView()
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        tableView = NSTableView()
        let column = NSTableColumn(identifier: .init("completion"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        if #available(macOS 11.0, *) {
            tableView.style = .fullWidth
        }

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: Self.contentPadding),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -Self.contentPadding),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        panel.contentView = effectView

        super.init()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clickRow)
    }

    func show(items: [CompletionItem], caretRect: NSRect, parentWindow: NSWindow) {
        self.items = items
        tableView.reloadData()

        let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var maxWidth: CGFloat = 0
        for item in items.prefix(40) {
            var width = (item.label as NSString).size(withAttributes: [.font: labelFont]).width
            if let detail = item.detail {
                width += (detail as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width + 24
            }
            maxWidth = max(maxWidth, width)
        }
        let width = min(max(maxWidth + 32, 240), 480)
        let rows = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(rows) * Self.rowHeight + Self.contentPadding * 2

        var origin = NSPoint(x: caretRect.minX - 12, y: caretRect.minY - height - 4)
        if let screen = parentWindow.screen {
            let visibleFrame = screen.visibleFrame
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - width)
            if origin.y < visibleFrame.minY {
                origin.y = caretRect.maxY + 4
            }
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)

        let wasVisible = panel.isVisible
        if panel.parent == nil {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        tableView.selectRowIndexes([0], byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        if !wasVisible {
            onVisibilityChange?(true)
        }
    }

    func move(to caretRect: NSRect, parentWindow: NSWindow) {
        var origin = NSPoint(x: caretRect.minX - 12, y: caretRect.minY - panel.frame.height - 4)
        if let screen = parentWindow.screen {
            let visibleFrame = screen.visibleFrame
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
            if origin.y < visibleFrame.minY {
                origin.y = caretRect.maxY + 4
            }
        }
        panel.setFrameOrigin(origin)
    }

    func hide() {
        guard panel.isVisible else {
            return
        }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
        onVisibilityChange?(false)
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else {
            return
        }
        var row = tableView.selectedRow + delta
        if row < 0 {
            row = items.count - 1
        } else if row >= items.count {
            row = 0
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func acceptSelection() -> Bool {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else {
            return false
        }
        let item = items[row]
        hide()
        onAccept?(item)
        return true
    }

    @objc private func clickRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else {
            return
        }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        _ = acceptSelection()
    }

    func numberOfRows(in _: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("CompletionRow")
        let cellView: CompletionRowView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? CompletionRowView {
            cellView = reused
        } else {
            cellView = CompletionRowView()
            cellView.identifier = identifier
        }
        cellView.bind(items[row])
        return cellView
    }
}

private final class CompletionRowView: NSTableCellView {
    private let labelField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(labelField)
        addSubview(detailField)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 12),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func bind(_ item: CompletionItem) {
        labelField.stringValue = item.label
        detailField.stringValue = item.detail ?? ""
    }
}
