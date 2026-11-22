import AppKit

let label = "local.fasttimemachine.backup"
let plistPath = "/Library/LaunchDaemons/\(label).plist"
let choices: [(String, Int)] = [
    ("15 minutes", 900),
    ("30 minutes", 1800),
    ("1 hour", 3600),
    ("2 hours", 7200),
    ("3 hours", 10800),
    ("4 hours", 14400),
    ("6 hours", 21600),
    ("12 hours", 43200),
    ("24 hours", 86400),
]

final class Menu: NSObject, NSApplicationDelegate {
    let program: String
    let editor: String
    let exclusions: String
    var window: NSWindow!
    let startAtLogin = NSButton(checkboxWithTitle: "Run a backup when the Mac starts", target: nil, action: nil)
    let period = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "")
    let startButton = NSButton(title: "Start backup", target: nil, action: nil)
    let installButton = NSButton(title: "Install", target: nil, action: nil)
    let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
    var suppressChange = false
    var jobInstalled = false
    var destinationConfigured = false
    var exclusionEditor: Editor?

    init(program: String, editor: String, exclusions: String) {
        self.program = program
        self.editor = editor
        self.exclusions = exclusions
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        build()
        loadSchedule()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil else { return }
        loadSchedule()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        exclusionEditor == nil
    }

    func build() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fast Time Machine Backup"
        window.center()
        guard let content = window.contentView else { return }

        startButton.target = self
        startButton.action = #selector(startBackup)
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.frame = NSRect(x: 20, y: 408, width: 440, height: 36)
        content.addSubview(startButton)

        let edit = NSButton(title: "Edit exclusions", target: self, action: #selector(editExclusions))
        edit.bezelStyle = .rounded
        edit.frame = NSRect(x: 20, y: 368, width: 440, height: 32)
        content.addSubview(edit)

        startAtLogin.target = self
        startAtLogin.action = #selector(scheduleChanged)
        startAtLogin.frame = NSRect(x: 20, y: 332, width: 440, height: 28)
        content.addSubview(startAtLogin)

        let periodTitle = NSTextField(wrappingLabelWithString: "Background job interval")
        periodTitle.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        periodTitle.frame = NSRect(x: 20, y: 302, width: 440, height: 22)
        content.addSubview(periodTitle)

        let periodNote = NSTextField(wrappingLabelWithString: "This applies only to the installed background job. Start backup runs one backup immediately and does not use this interval.")
        periodNote.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        periodNote.textColor = .secondaryLabelColor
        periodNote.frame = NSRect(x: 20, y: 250, width: 440, height: 46)
        content.addSubview(periodNote)

        let periodLabel = NSTextField(labelWithString: "Backup every")
        periodLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        periodLabel.setContentHuggingPriority(.required, for: .horizontal)
        period.target = self
        period.action = #selector(scheduleChanged)
        period.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (title, seconds) in choices {
            period.addItem(withTitle: title)
            period.item(at: period.numberOfItems - 1)?.representedObject = seconds
        }
        let periodRow = NSStackView(views: [periodLabel, period])
        periodRow.orientation = .horizontal
        periodRow.alignment = .centerY
        periodRow.spacing = 8
        periodRow.frame = NSRect(x: 20, y: 212, width: 440, height: 28)
        content.addSubview(periodRow)

        let note = NSTextField(wrappingLabelWithString: "Install adds the background job and runs a backup on the interval above. Uninstall removes that job and stops the automatic backups.")
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 20, y: 148, width: 440, height: 52)
        content.addSubview(note)

        installButton.target = self
        installButton.action = #selector(saveSchedule)
        installButton.bezelStyle = .rounded
        installButton.frame = NSRect(x: 20, y: 106, width: 210, height: 32)
        content.addSubview(installButton)

        uninstallButton.target = self
        uninstallButton.action = #selector(uninstall)
        uninstallButton.bezelStyle = .rounded
        uninstallButton.frame = NSRect(x: 250, y: 106, width: 210, height: 32)
        content.addSubview(uninstallButton)

        status.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 20, y: 16, width: 440, height: 78)
        content.addSubview(status)

        window.makeKeyAndOrderFront(nil)
    }

    func loadSchedule() {
        suppressChange = true
        defer { suppressChange = false }
        let installed = FileManager.default.fileExists(atPath: plistPath)
        var runAtLoad = false
        var interval = 3600
        if installed, let data = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
            interval = (plist["StartInterval"] as? Int) ?? 3600
        }
        jobInstalled = installed
        destinationConfigured = Self.timeMachineDestinationConfigured()
        installButton.isEnabled = destinationConfigured && !installed
        uninstallButton.isEnabled = installed
        startButton.isEnabled = destinationConfigured
        startAtLogin.isEnabled = destinationConfigured && installed
        startAtLogin.state = installed && runAtLoad ? .on : .off
        if let index = choices.firstIndex(where: { $0.1 == interval }) {
            period.selectItem(at: index)
        } else {
            period.insertItem(withTitle: "\(interval / 60) minutes", at: 0)
            period.item(at: 0)?.representedObject = interval
            period.selectItem(at: 0)
        }
        let loaded = launchctl(["print", "system/\(label)"])
        if !installed {
            showStatus("Background job is not installed.")
        } else if loaded.status == 0 {
            showStatus("Background job is installed.")
        } else {
            showStatus("The job file is present, but it is not loaded.")
        }
    }

    func showStatus(_ jobLine: String) {
        if destinationConfigured {
            status.stringValue = jobLine
        } else {
            status.stringValue = "No Time Machine destination configured. Set a destination in Time Machine Settings.\n" + jobLine
        }
    }

    static func timeMachineDestinationConfigured() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["destinationinfo"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.range(of: #"(?m)^ID[[:space:]]*:"#, options: .regularExpression) != nil
    }

    @objc func scheduleChanged() {
        guard jobInstalled, !suppressChange else { return }
        saveSchedule()
    }

    @objc func startBackup() {
        guard destinationConfigured else { return }
        let manualLabel = "local.fasttimemachine.backup.manual"
        let manualPlist = "/Library/LaunchDaemons/\(manualLabel).plist"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>Label</key>
        	<string>\(manualLabel)</string>
        	<key>ProgramArguments</key>
        	<array>
        		<string>\(program)</string>
        	</array>
        	<key>RunAtLoad</key>
        	<true/>
        	<key>StandardOutPath</key>
        	<string>/tmp/tmbackup-manual.out</string>
        	<key>StandardErrorPath</key>
        	<string>/tmp/tmbackup-manual.out</string>
        </dict>
        </plist>
        """
        let starter = FileManager.default.temporaryDirectory.appendingPathComponent("tmbackup-start.sh")
        let script = """
        #!/bin/bash
        set -e
        if /bin/launchctl print system/\(manualLabel) 2>/dev/null | /usr/bin/grep -q "state = running"; then
            exit 0
        fi
        cat > \(shellQuote(manualPlist)) << 'EOF'
        \(plist)
        EOF
        /bin/launchctl bootout system/\(manualLabel) >/dev/null 2>&1 || true
        /bin/launchctl bootstrap system \(shellQuote(manualPlist))
        rm -f \(shellQuote(manualPlist))
        """
        do {
            try script.write(to: starter, atomically: true, encoding: .utf8)
        } catch {
            alert("Could not start the backup.", error.localizedDescription)
            return
        }
        let result = admin("/bin/bash \(shellQuote(starter.path))")
        if result.status == -128 { return }
        if result.status == 0 {
            showStatus("Backup started. It keeps running after this window closes.")
        } else {
            alert("Could not start the backup.", result.output)
        }
    }

    @objc func editExclusions() {
        if exclusionEditor != nil { return }
        window.orderOut(nil)
        let editor = Editor(fileURL: URL(fileURLWithPath: exclusions))
        editor.onFinished = { [weak self] in
            guard let self else { return }
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.exclusionEditor = nil
            }
        }
        exclusionEditor = editor
        editor.show()
    }

    @objc func uninstall() {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            showStatus("Background job is not installed.")
            return
        }
        if backupIsRunning() {
            alert("A backup is running.", "Wait until it finishes, then uninstall.")
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Uninstall the background job?"
        confirm.informativeText = "Automatic backups stop. The app stays in Applications."
        confirm.addButton(withTitle: "Uninstall")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let script = """
        launchctl bootout system/\(label) || true
        rm -f "\(plistPath)"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmbackup-uninstall.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            alert("Could not uninstall.", error.localizedDescription)
            return
        }
        let result = admin("/bin/bash \(shellQuote(scriptURL.path))")
        if result.status == -128 { return }
        if result.status == 0 {
            loadSchedule()
            showStatus("Background job removed.")
        } else {
            alert("Could not uninstall.", result.output)
        }
    }

    @objc func saveSchedule() {
        guard destinationConfigured || jobInstalled else { return }
        if backupIsRunning() {
            alert("A backup is running.", "Wait until it finishes, then save the schedule.")
            return
        }
        let seconds = period.selectedItem?.representedObject as? Int ?? 3600
        let runAtLoad = startAtLogin.state == .on
        let finalPlist = plistXML(runAtLoad: runAtLoad, seconds: seconds)
        let loadPlist = plistXML(runAtLoad: false, seconds: seconds)
        let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmbackup-final.plist")
        let loadURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmbackup-load.plist")
        do {
            try finalPlist.write(to: finalURL, atomically: true, encoding: .utf8)
            try loadPlist.write(to: loadURL, atomically: true, encoding: .utf8)
        } catch {
            alert("Could not prepare the job.", error.localizedDescription)
            return
        }
        let script = """
        set -e
        cp "\(finalURL.path)" "\(plistPath)"
        chown root:wheel "\(plistPath)"
        chmod 644 "\(plistPath)"
        launchctl enable system/\(label) || true
        launchctl bootout system/\(label) || true
        cp "\(loadURL.path)" "\(plistPath)"
        launchctl bootstrap system "\(plistPath)"
        cp "\(finalURL.path)" "\(plistPath)"
        chown root:wheel "\(plistPath)"
        chmod 644 "\(plistPath)"
        """
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmbackup-install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            alert("Could not prepare the job.", error.localizedDescription)
            return
        }
        let result = admin("/bin/bash \(shellQuote(scriptURL.path))")
        if result.status == -128 {
            loadSchedule()
            return
        }
        if result.status == 0 {
            loadSchedule()
            showStatus("Background job installed.")
        } else {
            alert("Could not save the schedule.", result.output)
        }
    }

    func plistXML(runAtLoad: Bool, seconds: Int) -> String {
        let flag = runAtLoad ? "<true/>" : "<false/>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>Label</key>
        	<string>\(label)</string>
        	<key>ProgramArguments</key>
        	<array>
        		<string>\(program)</string>
        	</array>
        	<key>EnvironmentVariables</key>
        	<dict>
        		<key>PATH</key>
        		<string>/usr/bin:/bin:/usr/sbin:/sbin</string>
        	</dict>
        	<key>StartInterval</key>
        	<integer>\(seconds)</integer>
        	<key>RunAtLoad</key>
        	\(flag)
        </dict>
        </plist>
        """
    }

    func admin(_ command: String) -> (status: Int, output: String) {
        let source = "do shell script " + appleQuote(command) + " with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let text = (error[NSAppleScript.errorMessage] as? String) ?? "The change was cancelled."
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 1
            if number == -128 { return (number, "") }
            return (number, text)
        }
        return (0, result?.stringValue ?? "")
    }

    func backupIsRunning() -> Bool {
        if FileManager.default.fileExists(atPath: "/var/run/local.fasttimemachine.backup.lock") {
            return true
        }
        for name in [label, "local.fasttimemachine.backup.manual"] {
            if launchctl(["print", "system/\(name)"]).output.contains("state = running") {
                return true
            }
        }
        return false
    }

    func launchctl(_ args: [String]) -> (status: Int, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (Int(process.terminationStatus), String(data: data, encoding: .utf8) ?? "")
    }

    func alert(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.beginSheetModal(for: window)
    }

    func appleQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

var retainedMenu: Menu?

func launchMenu() {
    let bundle = Bundle.main
    let macos = (bundle.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
    let program = macos.appendingPathComponent("TimeMachineBackup").path
    let editor = macos.appendingPathComponent("EditExclusions").path
    let exclusions = (bundle.resourceURL ?? macos.deletingLastPathComponent().appendingPathComponent("Resources")).appendingPathComponent("exclusions.txt").path

    let app = NSApplication.shared
    let menu = Menu(program: program, editor: editor, exclusions: exclusions)
    retainedMenu = menu
    app.setActivationPolicy(.regular)
    app.delegate = menu
    app.run()
}
