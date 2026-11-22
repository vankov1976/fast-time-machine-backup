import AppKit

final class PathTableView: NSTableView {
    private var lockingHeight = false

    var contentHeight: CGFloat {
        guard numberOfRows > 0 else { return 0 }
        return rect(ofRow: numberOfRows - 1).maxY
    }

    override func setFrameSize(_ newSize: NSSize) {
        if lockingHeight {
            super.setFrameSize(newSize)
            return
        }
        var size = newSize
        let height = contentHeight
        if height > 0 { size.height = height }
        lockingHeight = true
        super.setFrameSize(size)
        lockingHeight = false
    }
}

final class Editor: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let fileURL: URL
    var onFinished: (() -> Void)?
    var paths: [String] = []
    var table: NSTableView!
    var window: NSWindow!
    var mainNote: NSTextField!
    var mainScroll: NSScrollView!
    var mainButtons: NSStackView!
    var settingsWindow: NSWindow?
    var settingsScroll: NSScrollView?
    var settingsButtons: NSStackView?
    var didFinish = false
    var settingsTimer: Timer?
    var settingsObserver: NSObjectProtocol?
    var sawSystemSettings = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func show() {
        load()
        buildWindow()
        window.delegate = self
        layoutMain()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        guard !didFinish else { return }
        didFinish = true
        window.delegate = nil
        let callback = onFinished
        onFinished = nil
        callback?()
    }

    deinit {
        settingsTimer?.invalidate()
        if let settingsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(settingsObserver)
        }
        window?.delegate = nil
        table = nil
        settingsWindow = nil
        window = nil
    }

    func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        paths = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#")
        }
        sortPaths()
    }

    func sortPaths() {
        paths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Extra exclusions"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.center()
        window.contentMinSize = NSSize(width: 640, height: 160)
        window.contentMaxSize = NSSize(width: 8000, height: 4000)

        let note = NSTextField(wrappingLabelWithString: "These paths are skipped only by the root backup. Time Machine Settings is a separate list.")
        note.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        note.alignment = .left
        mainNote = note

        let scroll = pathTable(paths)
        table = scroll.documentView as? NSTableView
        table.reloadData()
        table.tile()
        mainScroll = scroll

        let add = button("Add…", #selector(addPaths), key: "")
        let remove = button("Remove", #selector(removePaths), key: "\u{7f}")
        let settings = button("Time Machine Settings", #selector(showSettings), key: "")
        let cancel = button("Cancel", #selector(cancel), key: "\u{1b}")
        let save = button("Save", #selector(save), key: "\r")

        let row = NSStackView(views: [add, remove, settings, NSView(), cancel, save])
        row.orientation = .horizontal
        row.spacing = 8
        mainButtons = row

        let content = NSView()
        content.addSubview(note)
        content.addSubview(scroll)
        content.addSubview(row)
        window.contentView = content
        let rows = (table as? PathTableView)?.contentHeight ?? listHeight(paths.count)
        let height = min(preferredHeight(note: note, rowsHeight: rows, width: 920), screenCap())
        window.setContentSize(NSSize(width: 920, height: height))
        window.center()
        layoutMain()
        window.makeKeyAndOrderFront(nil)
    }

    func listHeight(_ rows: Int) -> CGFloat {
        CGFloat(rows) * 24
    }

    func screenCap() -> CGFloat {
        ((NSScreen.main)?.visibleFrame.height ?? 800) - 60
    }

    func preferredHeight(note: NSTextField?, rowsHeight: CGFloat, width: CGFloat) -> CGFloat {
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        var height = margin + 32 + margin
        if let note {
            let noteWidth = max(200, width - margin * 2)
            let noteHeight = ceil(note.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: noteWidth, height: 400)).height ?? 36)
            height += noteHeight + gap
        }
        if rowsHeight > 0 { height += rowsHeight + gap + 8 }
        return max(height, 160)
    }

    func place(note: NSTextField?, scroll: NSScrollView?, buttons: NSView, in content: NSView) {
        let bounds = content.bounds
        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let buttonH: CGFloat = 32
        let width = max(200, bounds.width - margin * 2)
        var top = bounds.height - margin
        if let note {
            let noteH = ceil(note.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 400)).height ?? 36)
            note.frame = NSRect(x: margin, y: top - noteH, width: width, height: noteH)
            top = note.frame.minY - gap
        }
        buttons.frame = NSRect(x: margin, y: margin, width: width, height: buttonH)
        let scrollH = max(24, top - (margin + buttonH + gap))
        scroll?.frame = NSRect(x: margin, y: margin + buttonH + gap, width: width, height: scrollH)
    }

    func layoutMain() {
        guard let content = window.contentView else { return }
        place(note: mainNote, scroll: mainScroll, buttons: mainButtons, in: content)
    }

    func layoutSettings() {
        guard let sheet = settingsWindow, let content = sheet.contentView, let buttons = settingsButtons else { return }
        place(note: nil, scroll: settingsScroll, buttons: buttons, in: content)
    }

    func windowDidResize(_ notification: Notification) {
        guard let resized = notification.object as? NSWindow else { return }
        if resized === window { layoutMain() }
        if resized === settingsWindow { layoutSettings() }
    }

    func pathTable(_ rows: [String]) -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "Path"
        column.resizingMask = .autoresizingMask
        column.width = measuredWidth(rows)
        column.minWidth = 400

        let table = PathTableView()
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.intercellSpacing = NSSize(width: 8, height: 2)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        if #available(macOS 11.0, *) {
            table.style = .plain
        }
        return scroll
    }

    func measuredWidth(_ rows: [String]) -> CGFloat {
        let font = NSFont.userFixedPitchFont(ofSize: 13) ?? NSFont.systemFont(ofSize: 13)
        let longest = rows.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 600
        return max(860, longest + 32)
    }

    func button(_ title: String, _ action: Selector, key: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = key
        return button
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === table { return paths.count }
        return settingsPaths.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("path")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        let value = tableView === table ? paths[row] : settingsPaths[row]
        cell.textField?.stringValue = value
        return cell
    }

    func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.userFixedPitchFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    var settingsPaths: [String] = []

    @objc func addPaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders or files to exclude from the root backup."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            for url in panel.urls where !self.paths.contains(url.path) {
                self.paths.append(url.path)
            }
            self.sortPaths()
            self.fitColumn(self.table, rows: self.paths)
            self.table.reloadData()
            self.table.tile()
            self.layoutMain()
        }
    }

    @objc func removePaths() {
        let selected = table.selectedRowIndexes
        guard !selected.isEmpty else { return }
        paths = paths.enumerated().compactMap { selected.contains($0.offset) ? nil : $0.element }
        table.reloadData()
        table.tile()
        layoutMain()
    }

    func fitColumn(_ tableView: NSTableView?, rows: [String]) {
        guard let column = tableView?.tableColumns.first else { return }
        column.width = measuredWidth(rows)
    }

    @objc func showSettings() {
        settingsPaths = readSettings().sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let width = min(NSScreen.main?.visibleFrame.width ?? 1200, max(720, measuredWidth(settingsPaths) + 48))
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "Time Machine Settings"
        sheet.isReleasedWhenClosed = false
        sheet.animationBehavior = .none
        sheet.contentMinSize = NSSize(width: 720, height: 140)
        sheet.contentMaxSize = NSSize(width: 8000, height: 4000)
        sheet.delegate = self
        settingsWindow = sheet

        let scroll = pathTable(settingsPaths)
        let settingsTable = scroll.documentView as? NSTableView
        settingsTable?.reloadData()
        settingsTable?.tile()
        settingsScroll = scroll

        let open = button("Open System Settings", #selector(openSystemSettings), key: "")
        let close = button("Close", #selector(closeSettings(_:)), key: "\u{1b}")
        let row = NSStackView(views: [open, NSView(), close])
        row.orientation = .horizontal
        row.spacing = 8
        settingsButtons = row

        let content = NSView()
        if settingsPaths.isEmpty {
            let empty = NSTextField(labelWithString: "Time Machine Settings has no exclusions.")
            empty.textColor = .secondaryLabelColor
            content.addSubview(empty)
            content.addSubview(row)
            sheet.contentView = content
            let height = preferredHeight(note: empty, rowsHeight: 0, width: width)
            sheet.setContentSize(NSSize(width: width, height: height))
            place(note: empty, scroll: nil, buttons: row, in: content)
        } else {
            content.addSubview(scroll)
            content.addSubview(row)
            sheet.contentView = content
            let rows = (settingsTable as? PathTableView)?.contentHeight ?? listHeight(settingsPaths.count)
            let height = min(preferredHeight(note: nil, rowsHeight: rows, width: width), screenCap())
            sheet.setContentSize(NSSize(width: width, height: height))
            layoutSettings()
        }
        window.beginSheet(sheet)
    }

    func readSettings() -> [String] {
        let settingsURL = URL(fileURLWithPath: "/Library/Preferences/com.apple.TimeMachine.plist")
        if let data = try? Data(contentsOf: settingsURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let skip = plist["SkipPaths"] as? [String], !skip.isEmpty {
            return skip
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", settingsURL.path, "SkipPaths"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\","))
        }.filter { $0.hasPrefix("/") }
    }

    @objc func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension",
            "x-apple.systempreferences:com.apple.TimeMachine-Settings.extension",
        ]
        var opened = false
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                opened = true
                break
            }
        }
        if !opened {
            opened = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/TimeMachine.prefPane"))
        }
        if opened { watchSystemSettings() }
    }

    func watchSystemSettings() {
        settingsTimer?.invalidate()
        if let settingsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(settingsObserver)
        }
        sawSystemSettings = false
        settingsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? ""
            if id == "com.apple.systempreferences" || id == "com.apple.SystemSettings" {
                self?.returnFromSystemSettings()
            }
        }
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.systemSettingsIsOpen() {
                self.sawSystemSettings = true
            } else if self.sawSystemSettings {
                self.returnFromSystemSettings()
            }
        }
    }

    func systemSettingsIsOpen() -> Bool {
        let ids = ["com.apple.systempreferences", "com.apple.SystemSettings"]
        let pids = Set(NSWorkspace.shared.runningApplications.compactMap { app -> Int32? in
            ids.contains(app.bundleIdentifier ?? "") ? app.processIdentifier : nil
        })
        guard !pids.isEmpty else { return false }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return info.contains { item in
            let pid = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            return pids.contains(pid) && layer == 0
        }
    }

    func returnFromSystemSettings() {
        settingsTimer?.invalidate()
        settingsTimer = nil
        if let settingsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        sawSystemSettings = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func closeSettings(_ sender: NSButton) {
        if let sheet = sender.window {
            window.endSheet(sheet)
        }
    }

    @objc func cancel() {
        window.close()
    }

    @objc func save() {
        sortPaths()
        let header = """
        # Extra exclusions for the root backup. One path per line.
        # Lines starting with # are ignored.
        # Time Machine Settings is a separate list and is not changed here.

        """
        let body = header + paths.joined(separator: "\n") + (paths.isEmpty ? "" : "\n")
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            window.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save the list"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }
}
