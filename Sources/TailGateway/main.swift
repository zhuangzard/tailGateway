import AppKit
import Foundation

private let appSupportDirPath = "\(NSHomeDirectory())/Library/Application Support/TailGateway"
private let tailGatewayCtlPath = "\(appSupportDirPath)/bin/tailgatewayctl"
private let tailGatewayAutoPath = "\(appSupportDirPath)/bin/tailgateway-auto"
private let helperDirPath = "\(appSupportDirPath)/Engine"
private let launchAgentPath = "\(NSHomeDirectory())/Library/LaunchAgents/com.taisen.tailgateway.restore.plist"
private let launchAgentLabel = "com.taisen.tailgateway.restore"
private let appLaunchAgentPath = "\(NSHomeDirectory())/Library/LaunchAgents/com.taisen.tailgateway.plist"
private let appLaunchAgentLabel = "com.taisen.tailgateway"
private let autostartLogPath = "\(NSHomeDirectory())/Library/Logs/TailGateway.autostart.log"

extension Notification.Name {
    static let tailGatewayStatusChanged = Notification.Name("tailGatewayStatusChanged")
}

struct CommandResult {
    let code: Int32
    let output: String
}

@discardableResult
func runCommand(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return CommandResult(code: 127, output: "Failed to run \(executable): \(error.localizedDescription)")
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return CommandResult(code: process.terminationStatus, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
}

func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

func listEntries(at path: String) -> [String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

func writeListEntries(_ entries: [String], to path: String) throws {
    let text = entries.joined(separator: "\n") + "\n"
    try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func sanitizedHost(_ value: String) -> String {
    var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: host), let parsedHost = url.host {
        host = parsedHost
    }
    host = host.replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "*.", with: "")
    if let slash = host.firstIndex(of: "/") {
        host = String(host[..<slash])
    }
    return host.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
}

func sanitizedIPv4(_ value: String) -> String? {
    var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let commentStart = candidate.firstIndex(of: "#") {
        candidate = String(candidate[..<commentStart]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let url = URL(string: candidate), let host = url.host {
        candidate = host
    }
    if let slash = candidate.firstIndex(of: "/") {
        candidate = String(candidate[..<slash])
    }

    let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }

    var normalizedParts: [String] = []
    for part in parts {
        guard !part.isEmpty, part.allSatisfy({ $0.isNumber }), let value = Int(part), (0...255).contains(value) else {
            return nil
        }
        normalizedParts.append(String(value))
    }
    return normalizedParts.joined(separator: ".")
}

func tailMode(from output: String) -> String {
    if let tailMode = output.components(separatedBy: .newlines)
        .first(where: { $0.contains("Last tail mode:") })?
        .replacingOccurrences(of: "Last tail mode:", with: "")
        .trimmingCharacters(in: .whitespaces) {
        switch tailMode {
        case "on":
            return "china"
        case "off":
            return "usa"
        default:
            return "unknown"
        }
    }

    return output.components(separatedBy: .newlines)
        .first(where: { $0.contains("Last bridge mode:") })?
        .replacingOccurrences(of: "Last bridge mode:", with: "")
        .trimmingCharacters(in: .whitespaces) ?? "unknown"
}

func pingSummary(host: String, result: CommandResult) -> String {
    if result.code != 0 {
        return "Ping \(host) failed: \(result.output)"
    }

    let lines = result.output.components(separatedBy: .newlines)
    if let stats = lines.first(where: { $0.contains("round-trip") || $0.contains("rtt ") }) {
        return "\(host): \(stats)"
    }
    return "\(host): \(result.output)"
}

final class TailModeButton: NSButton {
    var fillColor = NSColor(calibratedRed: 0.18, green: 0.50, blue: 0.95, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = isHighlighted
            ? fillColor.blended(withFraction: 0.14, of: .black) ?? fillColor
            : fillColor
        let path = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        color.setFill()
        path.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textSize = title.size(withAttributes: attributes)
        let iconSize: CGFloat = (title.hasPrefix("Start") || title.hasPrefix("Stop")) ? 14 : 0
        let iconGap: CGFloat = iconSize > 0 ? 14 : 0
        let groupWidth = iconSize + iconGap + textSize.width
        let startX = (bounds.width - groupWidth) / 2

        if title.hasPrefix("Start") {
            let centerY = bounds.midY
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: startX, y: centerY - 9))
            triangle.line(to: NSPoint(x: startX, y: centerY + 9))
            triangle.line(to: NSPoint(x: startX + 16, y: centerY))
            triangle.close()
            NSColor.white.setFill()
            triangle.fill()
        } else if title.hasPrefix("Stop") {
            let iconRect = NSRect(x: startX, y: bounds.midY - 7, width: 14, height: 14)
            let square = NSBezierPath(roundedRect: iconRect, xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            square.fill()
        }

        let textRect = NSRect(
            x: startX + iconSize + iconGap,
            y: (bounds.height - textSize.height) / 2 - 1,
            width: textSize.width + 2,
            height: textSize.height + 4
        )
        title.draw(in: textRect, withAttributes: attributes)
    }
}

@MainActor
final class TailGatewayApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Checking status...", action: nil, keyEquivalent: "")
    private lazy var toggleTailModeItem = NSMenuItem(title: "Turn Tail Mode On", action: #selector(toggleTailMode), keyEquivalent: "t")
    private lazy var openWindowItem = NSMenuItem(title: "Open TailGateway...", action: #selector(openMainWindow), keyEquivalent: "g")
    private let launchAtLoginItem = NSMenuItem(title: "Launch TailGateway at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let autoRestoreItem = NSMenuItem(title: "Restore Last Tail Mode at Login", action: #selector(toggleAutoRestore), keyEquivalent: "")
    private let busyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var isOperationRunning = false
    private var currentMode = "unknown"
    private lazy var mainWindowController = TailGatewayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatusAction), name: .tailGatewayStatusChanged, object: nil)
        refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = foxTailImage(isOn: false)
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "TailGateway"
        }
        statusItem.length = 28
    }

    private func buildMenu() {
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        busyItem.isEnabled = false
        busyItem.isHidden = true
        menu.addItem(busyItem)
        menu.addItem(.separator())

        menu.addItem(toggleTailModeItem)
        menu.addItem(openWindowItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit TailGateway", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleTailMode() {
        if currentMode == "china" {
            runBridgeMode("off", title: "Turn Tail Mode Off")
        } else {
            runBridgeMode("on", title: "Turn Tail Mode On")
        }
    }

    @objc private func refreshStatusAction() {
        refreshStatus()
    }

    @objc private func openMainWindow() {
        mainWindowController.showWindow(nil)
        mainWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func runBridgeMode(_ mode: String, title: String) {
        guard !isOperationRunning else {
            showMessage("TailGateway", "A mode switch is already running. Wait for it to finish, then refresh status.")
            return
        }

        isOperationRunning = true
        setModeItemsEnabled(false)
        setBusy("\(title) is running...")
        if mode == "on" || mode == "off" {
            updateStatusIcon(mode: mode == "on" ? "china" : "usa")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand(tailGatewayCtlPath, [mode])
            DispatchQueue.main.async {
                self.isOperationRunning = false
                self.setModeItemsEnabled(true)
                self.clearBusy()
                self.refreshStatus()
                NotificationCenter.default.post(name: .tailGatewayStatusChanged, object: nil)
                if result.code != 0 {
                    self.showResult(title, result)
                }
            }
        }
    }

    private func refreshStatus() {
        DispatchQueue.global(qos: .utility).async {
            let result = runCommand(tailGatewayCtlPath, ["status"])
            DispatchQueue.main.async {
                let summary = self.statusSummary(from: result.output)
                let mode = self.lastMode(from: result.output)
                if !self.isOperationRunning {
                    self.currentMode = mode
                    self.statusMenuItem.title = summary
                    self.updateStatusIcon(mode: mode)
                    self.updateToggleMenuItem(mode: mode)
                }
            }
        }
    }

    private func statusSummary(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let mode = displayMode(lastMode(from: output))
        let routes = lines.first(where: { $0.contains("Local direct route count:") })?
            .replacingOccurrences(of: "Local direct route count:", with: "")
            .trimmingCharacters(in: .whitespaces) ?? "?"
        return "Tail Mode: \(mode) · Direct Routes: \(routes)"
    }

    private func lastMode(from output: String) -> String {
        tailMode(from: output)
    }

    private func displayMode(_ mode: String) -> String {
        switch mode {
        case "china":
            return "On"
        case "usa":
            return "Off"
        case "not recorded":
            return "Off"
        default:
            return "Unknown"
        }
    }

    private func updateStatusIcon(mode: String) {
        guard let button = statusItem.button else { return }
        let isOn = mode == "china"
        button.image = foxTailImage(isOn: isOn)
        button.title = ""
        button.toolTip = "TailGateway: Tail Mode \(isOn ? "On" : "Off")"
        statusItem.length = 28
    }

    private func updateToggleMenuItem(mode: String) {
        toggleTailModeItem.title = mode == "china" ? "Turn Tail Mode Off" : "Turn Tail Mode On"
        toggleTailModeItem.keyEquivalent = "t"
    }

    private func foxTailImage(isOn: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        let bodyColor = isOn
            ? NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.12, alpha: 1.0)
            : NSColor.systemGray
        let tipColor = isOn ? NSColor.white : NSColor(calibratedWhite: 0.82, alpha: 1.0)

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.3, y: 4.0))
        tail.curve(to: NSPoint(x: 17.9, y: 18.2), controlPoint1: NSPoint(x: 3.7, y: 10.6), controlPoint2: NSPoint(x: 8.3, y: 18.7))
        tail.curve(to: NSPoint(x: 18.4, y: 6.7), controlPoint1: NSPoint(x: 21.0, y: 14.8), controlPoint2: NSPoint(x: 21.0, y: 9.4))
        tail.curve(to: NSPoint(x: 4.3, y: 4.0), controlPoint1: NSPoint(x: 14.6, y: 2.8), controlPoint2: NSPoint(x: 8.4, y: 2.1))
        tail.close()
        bodyColor.setFill()
        tail.fill()

        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: 13.8, y: 16.5))
        tip.curve(to: NSPoint(x: 18.1, y: 18.2), controlPoint1: NSPoint(x: 15.1, y: 18.0), controlPoint2: NSPoint(x: 16.8, y: 18.7))
        tip.curve(to: NSPoint(x: 17.5, y: 13.2), controlPoint1: NSPoint(x: 19.0, y: 16.6), controlPoint2: NSPoint(x: 18.6, y: 14.6))
        tip.curve(to: NSPoint(x: 13.8, y: 16.5), controlPoint1: NSPoint(x: 16.1, y: 14.4), controlPoint2: NSPoint(x: 14.9, y: 15.5))
        tip.close()
        tipColor.setFill()
        tip.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func importIPCIDRWhitelist() {
        importList(
            title: "Import IP CIDR Whitelist",
            destinationName: "cn-ip-list.txt",
            allowedExtensions: ["txt", "list", "conf"]
        )
    }

    @objc private func importDomainWhitelist() {
        importList(
            title: "Import Domain Whitelist",
            destinationName: "cn-fast-route-domains.txt",
            allowedExtensions: ["txt", "list", "conf"]
        )
    }

    @objc private func importDNSSplitDomainList() {
        importList(
            title: "Import DNS Split Domain List",
            destinationName: "cn-domains-for-local-dns.txt",
            allowedExtensions: ["txt", "list", "conf"]
        )
    }

    private func importList(title: String, destinationName: String, allowedExtensions: [String]) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.allowedFileTypes = allowedExtensions

        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: helperDirPath, withIntermediateDirectories: true)
            let destination = URL(fileURLWithPath: helperDirPath).appendingPathComponent(destinationName)
            if fileManager.fileExists(atPath: destination.path) {
                let backup = destination.deletingLastPathComponent().appendingPathComponent("\(destinationName).bak.\(timestamp())")
                try fileManager.copyItem(at: destination, to: backup)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            showMessage(title, "Imported \(source.lastPathComponent) to \(destination.path). Turn Tail Mode On to apply route changes.")
        } catch {
            showMessage(title, "Import failed: \(error.localizedDescription)")
        }
    }

    @objc private func installDNSSplit() {
        setBusy("Installing DNS split...")
        DispatchQueue.global(qos: .userInitiated).async {
            let script = "\(helperDirPath)/apply-cn-dns-split.zsh"
            let list = "\(helperDirPath)/cn-domains-for-local-dns.txt"
            let command = "/bin/zsh \(shellQuote(script)) \(shellQuote(list)) 223.5.5.5 119.29.29.29"
            let result = runCommand("/usr/bin/osascript", [
                "-e",
                "do shell script \(shellQuote(command)) with administrator privileges"
            ])
            DispatchQueue.main.async {
                self.clearBusy()
                self.refreshStatus()
                self.showResult("Install / Refresh DNS Split", result)
            }
        }
    }

    @objc private func toggleAutoRestore() {
        if isAutoRestoreLoaded() {
            let result = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            autoRestoreItem.state = .off
            showResult("Auto Restore Disabled", result)
        } else {
            ensureLaunchAgentExists()
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            let result = runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath])
            _ = runCommand("/bin/launchctl", ["enable", "gui/\(getuid())/\(launchAgentLabel)"])
            autoRestoreItem.state = isAutoRestoreLoaded() ? .on : .off
            showResult("Auto Restore Enabled", result)
        }
        refreshStatus()
    }

    @objc private func toggleLaunchAtLogin() {
        if isAppLaunchLoaded() {
            let result = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", appLaunchAgentPath])
            launchAtLoginItem.state = .off
            showResult("Launch at Login Disabled", result)
        } else {
            ensureAppLaunchAgentExists()
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", appLaunchAgentPath])
            let result = runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", appLaunchAgentPath])
            _ = runCommand("/bin/launchctl", ["enable", "gui/\(getuid())/\(appLaunchAgentLabel)"])
            launchAtLoginItem.state = isAppLaunchLoaded() ? .on : .off
            showResult("Launch at Login Enabled", result)
        }
        refreshStatus()
    }

    private func ensureAppLaunchAgentExists() {
        let executable = Bundle.main.executablePath ?? "\(NSHomeDirectory())/Applications/TailGateway.app/Contents/MacOS/TailGateway"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(appLaunchAgentLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executable)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>StandardOutPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.launchd.out.log</string>
          <key>StandardErrorPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.launchd.err.log</string>
        </dict>
        </plist>
        """
        do {
            let agentDir = URL(fileURLWithPath: appLaunchAgentPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            try plist.write(toFile: appLaunchAgentPath, atomically: true, encoding: .utf8)
        } catch {
            showMessage("Launch at Login", "Could not create LaunchAgent: \(error.localizedDescription)")
        }
    }

    private func isAppLaunchLoaded() -> Bool {
        runCommand("/bin/launchctl", ["print", "gui/\(getuid())/\(appLaunchAgentLabel)"]).code == 0
    }

    private func ensureLaunchAgentExists() {
        guard !FileManager.default.fileExists(atPath: launchAgentPath) else { return }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(launchAgentLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(tailGatewayAutoPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.restore.launchd.out.log</string>
          <key>StandardErrorPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.restore.launchd.err.log</string>
        </dict>
        </plist>
        """
        do {
            let agentDir = URL(fileURLWithPath: launchAgentPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            try plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } catch {
            showMessage("Auto Restore", "Could not create LaunchAgent: \(error.localizedDescription)")
        }
    }

    private func isAutoRestoreLoaded() -> Bool {
        runCommand("/bin/launchctl", ["print", "gui/\(getuid())/\(launchAgentLabel)"]).code == 0
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: helperDirPath))
    }

    @objc private func openAutostartLog() {
        let url = URL(fileURLWithPath: autostartLogPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            showMessage("Autostart Log", "No log file yet at \(autostartLogPath).")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setBusy(_ message: String) {
        statusMenuItem.title = message
        busyItem.title = message
        busyItem.isHidden = false
    }

    private func clearBusy() {
        busyItem.isHidden = true
    }

    private func setModeItemsEnabled(_ enabled: Bool) {
        toggleTailModeItem.isEnabled = enabled
        openWindowItem.isEnabled = enabled
    }

    private func showResult(_ title: String, _ result: CommandResult) {
        let message = result.output.isEmpty ? "Exit code: \(result.code)" : result.output
        showMessage(title, message)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class TailGatewayWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let listSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let domainField = NSTextField()
    private let pinnedField = NSTextField()
    private let pingHostField = NSTextField(string: "baidu.com")
    private let pingResultLabel = NSTextField(wrappingLabelWithString: "Ping result: not run yet")
    private let tableView = NSTableView()
    private let pinnedTableView = NSTableView()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch TailGateway at login", target: nil, action: nil)
    private let restoreAtLoginCheckbox = NSButton(checkboxWithTitle: "Restore last Tail Mode at login", target: nil, action: nil)
    private let toggleButton = TailModeButton(title: "Start Tail Mode", target: nil, action: nil)
    private var domainEntries: [String] = []
    private var pinnedEntries: [String] = []
    private var currentMode = "unknown"
    private var isWorking = false

    private var cidrListPath: String { "\(helperDirPath)/cn-ip-list.txt" }
    private var domainListPath: String { "\(helperDirPath)/cn-fast-route-domains.txt" }
    private var pinnedHostsPath: String { "\(helperDirPath)/pinned-hosts.txt" }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TailGateway"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
        refreshAll()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .tailGatewayStatusChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshAll()
        super.showWindow(sender)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        toggleButton.target = self
        toggleButton.action = #selector(toggleTailMode)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toggleButton.widthAnchor.constraint(equalToConstant: 380),
            toggleButton.heightAnchor.constraint(equalToConstant: 72)
        ])
        updateMainToggleButton(mode: "usa", isWorking: false)
        root.addArrangedSubview(horizontalStack([toggleButton, spacer()]))

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(statusLabel)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        restoreAtLoginCheckbox.target = self
        restoreAtLoginCheckbox.action = #selector(toggleAutoRestore)
        root.addArrangedSubview(horizontalStack([launchAtLoginCheckbox, restoreAtLoginCheckbox, spacer()]))

        listSummaryLabel.font = .systemFont(ofSize: 13)
        root.addArrangedSubview(listSummaryLabel)

        let cidrRow = horizontalStack([
            NSTextField(labelWithString: "IP CIDR whitelist"),
            spacer(),
            button("Import CIDR List...", #selector(importCIDRList)),
            button("Export CIDR List...", #selector(exportCIDRList))
        ])
        root.addArrangedSubview(cidrRow)

        let pinnedTitle = NSTextField(labelWithString: "Pinned IP whitelist")
        pinnedTitle.font = .systemFont(ofSize: 15, weight: .medium)
        root.addArrangedSubview(horizontalStack([
            pinnedTitle,
            spacer(),
            button("Import Pinned IPs...", #selector(importPinnedHosts)),
            button("Export Pinned IPs...", #selector(exportPinnedHosts))
        ]))

        let pinnedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pinnedIP"))
        pinnedColumn.title = "Pinned IP"
        pinnedColumn.width = 680
        pinnedTableView.addTableColumn(pinnedColumn)
        pinnedTableView.headerView = nil
        pinnedTableView.delegate = self
        pinnedTableView.dataSource = self
        pinnedTableView.usesAlternatingRowBackgroundColors = true

        let pinnedScrollView = NSScrollView()
        pinnedScrollView.hasVerticalScroller = true
        pinnedScrollView.documentView = pinnedTableView
        pinnedScrollView.translatesAutoresizingMaskIntoConstraints = false
        pinnedScrollView.heightAnchor.constraint(equalToConstant: 92).isActive = true
        root.addArrangedSubview(pinnedScrollView)

        pinnedField.placeholderString = "128.14.14.141"
        pinnedField.translatesAutoresizingMaskIntoConstraints = false
        pinnedField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        root.addArrangedSubview(horizontalStack([
            pinnedField,
            button("Add IP", #selector(addPinnedIP)),
            button("Update Selected IP", #selector(updateSelectedPinnedIP)),
            button("Delete Selected IP", #selector(deleteSelectedPinnedIP)),
            spacer()
        ]))

        let domainTitle = NSTextField(labelWithString: "Domain whitelist")
        domainTitle.font = .systemFont(ofSize: 15, weight: .medium)
        root.addArrangedSubview(domainTitle)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("domain"))
        column.title = "Website"
        column.width = 680
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        root.addArrangedSubview(scrollView)

        domainField.placeholderString = "example.com"
        domainField.translatesAutoresizingMaskIntoConstraints = false
        domainField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        root.addArrangedSubview(horizontalStack([
            domainField,
            button("Add Website", #selector(addWebsite)),
            button("Delete Selected", #selector(deleteSelectedWebsite)),
            button("Import Domains...", #selector(importDomainList)),
            button("Export Domains...", #selector(exportDomainList))
        ]))

        let pingTitle = NSTextField(labelWithString: "Ping speed check")
        pingTitle.font = .systemFont(ofSize: 15, weight: .medium)
        root.addArrangedSubview(pingTitle)

        pingHostField.placeholderString = "baidu.com"
        pingHostField.translatesAutoresizingMaskIntoConstraints = false
        pingHostField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        root.addArrangedSubview(horizontalStack([
            pingHostField,
            button("Ping", #selector(runPingCheck)),
            button("Use Selected Website", #selector(useSelectedWebsiteForPing)),
            spacer()
        ]))

        pingResultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pingResultLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(pingResultLabel)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func horizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    @objc private func refreshAll() {
        refreshStatus()
        refreshLists()
        launchAtLoginCheckbox.state = isAppLaunchLoaded() ? .on : .off
        restoreAtLoginCheckbox.state = isAutoRestoreLoaded() ? .on : .off
    }

    private func refreshStatus() {
        DispatchQueue.global(qos: .utility).async {
            let result = runCommand(tailGatewayCtlPath, ["status"])
            let output = result.output
            let mode = tailMode(from: output)
            let routes = output.components(separatedBy: .newlines)
                .first(where: { $0.contains("Local direct route count:") })?
                .replacingOccurrences(of: "Local direct route count:", with: "")
                .trimmingCharacters(in: .whitespaces) ?? "?"
            let dns = output.components(separatedBy: .newlines)
                .first(where: { $0.contains("DNS split:") })?
                .replacingOccurrences(of: "DNS split:", with: "")
                .trimmingCharacters(in: .whitespaces) ?? "unknown"

            DispatchQueue.main.async {
                self.currentMode = mode
                self.updateMainToggleButton(mode: mode, isWorking: false)
                self.statusLabel.stringValue = "Tail Mode: \(mode == "china" ? "On" : "Off") · Direct Routes: \(routes) · DNS Split: \(dns)"
            }
        }
    }

    private func refreshLists() {
        domainEntries = listEntries(at: domainListPath)
        pinnedEntries = listEntries(at: pinnedHostsPath)
        tableView.reloadData()
        pinnedTableView.reloadData()

        let cidrCount = listEntries(at: cidrListPath).count
        listSummaryLabel.stringValue = "Imported lists: \(cidrCount) CIDR entries · \(domainEntries.count) domain entries · \(pinnedEntries.count) pinned IPs"
    }

    @objc private func toggleTailMode() {
        guard !isWorking else { return }
        isWorking = true
        toggleButton.isEnabled = false
        let targetMode = currentMode == "china" ? "off" : "on"
        updateMainToggleButton(mode: targetMode == "on" ? "china" : "usa", isWorking: true)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand(tailGatewayCtlPath, [targetMode])
            DispatchQueue.main.async {
                self.isWorking = false
                self.toggleButton.isEnabled = true
                self.refreshAll()
                NotificationCenter.default.post(name: .tailGatewayStatusChanged, object: nil)
                if result.code != 0 {
                    self.showResult("Tail Mode", result)
                }
            }
        }
    }

    private func updateMainToggleButton(mode: String, isWorking: Bool) {
        let isOn = mode == "china"
        if isWorking {
            toggleButton.title = isOn ? "Starting Tail Mode..." : "Stopping Tail Mode..."
            toggleButton.fillColor = .systemGray
        } else if isOn {
            toggleButton.title = "Stop Tail Mode"
            toggleButton.fillColor = NSColor(calibratedRed: 0.18, green: 0.50, blue: 0.95, alpha: 1.0)
        } else {
            toggleButton.title = "Start Tail Mode"
            toggleButton.fillColor = NSColor(calibratedRed: 0.18, green: 0.50, blue: 0.95, alpha: 1.0)
        }
        toggleButton.needsDisplay = true
    }

    @objc private func addWebsite() {
        let host = sanitizedHost(domainField.stringValue)
        guard !host.isEmpty else { return }
        guard host.contains(".") else {
            showMessage("Add Website", "Enter a full domain like bilibili.com.")
            return
        }
        guard !domainEntries.contains(host) else {
            showMessage("Add Website", "\(host) is already in the whitelist.")
            return
        }

        domainEntries.append(host)
        domainEntries.sort()
        saveDomains()
        domainField.stringValue = ""
        refreshLists()
    }

    @objc private func deleteSelectedWebsite() {
        let row = tableView.selectedRow
        guard row >= 0 && row < domainEntries.count else { return }
        domainEntries.remove(at: row)
        saveDomains()
        refreshLists()
    }

    @objc private func addPinnedIP() {
        guard let ip = pinnedIPFromField(title: "Add Pinned IP") else { return }
        guard !pinnedEntries.contains(ip) else {
            showMessage("Add Pinned IP", "\(ip) is already in the pinned IP whitelist.")
            return
        }

        pinnedEntries.append(ip)
        savePinnedHosts()
        pinnedField.stringValue = ""
        refreshLists()
    }

    @objc private func updateSelectedPinnedIP() {
        let row = pinnedTableView.selectedRow
        guard row >= 0 && row < pinnedEntries.count else { return }
        guard let ip = pinnedIPFromField(title: "Update Pinned IP") else { return }
        if let existingIndex = pinnedEntries.firstIndex(of: ip), existingIndex != row {
            showMessage("Update Pinned IP", "\(ip) is already in the pinned IP whitelist.")
            return
        }

        pinnedEntries[row] = ip
        savePinnedHosts()
        pinnedField.stringValue = ""
        refreshLists()
    }

    @objc private func deleteSelectedPinnedIP() {
        let row = pinnedTableView.selectedRow
        guard row >= 0 && row < pinnedEntries.count else { return }
        pinnedEntries.remove(at: row)
        savePinnedHosts()
        pinnedField.stringValue = ""
        refreshLists()
    }

    @objc private func useSelectedWebsiteForPing() {
        let row = tableView.selectedRow
        guard row >= 0 && row < domainEntries.count else { return }
        pingHostField.stringValue = domainEntries[row]
    }

    @objc private func importDomainList() {
        importList(title: "Import Domain Whitelist", destinationPath: domainListPath)
    }

    @objc private func exportDomainList() {
        exportList(title: "Export Domain Whitelist", defaultName: "tailgateway-domain-whitelist.txt", sourcePath: domainListPath)
    }

    @objc private func importCIDRList() {
        importList(title: "Import IP CIDR Whitelist", destinationPath: cidrListPath)
    }

    @objc private func exportCIDRList() {
        exportList(title: "Export IP CIDR Whitelist", defaultName: "tailgateway-cidr-whitelist.txt", sourcePath: cidrListPath)
    }

    @objc private func importPinnedHosts() {
        importList(title: "Import Pinned IP Whitelist", destinationPath: pinnedHostsPath)
    }

    @objc private func exportPinnedHosts() {
        exportList(title: "Export Pinned IP Whitelist", defaultName: "tailgateway-pinned-ips.txt", sourcePath: pinnedHostsPath)
    }

    private func importList(title: String, destinationPath: String) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["txt", "list", "conf"]

        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let destination = URL(fileURLWithPath: destinationPath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                let backup = destination.deletingLastPathComponent().appendingPathComponent("\(destination.lastPathComponent).bak.\(timestamp())")
                try FileManager.default.copyItem(at: destination, to: backup)
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            refreshLists()
        } catch {
            showMessage(title, "Import failed: \(error.localizedDescription)")
        }
    }

    private func exportList(title: String, defaultName: String, sourcePath: String) {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: destination)
        } catch {
            showMessage(title, "Export failed: \(error.localizedDescription)")
        }
    }

    private func saveDomains() {
        do {
            try writeListEntries(domainEntries, to: domainListPath)
        } catch {
            showMessage("Domain Whitelist", "Save failed: \(error.localizedDescription)")
        }
    }

    private func savePinnedHosts() {
        do {
            try writeListEntries(pinnedEntries, to: pinnedHostsPath)
        } catch {
            showMessage("Pinned IP Whitelist", "Save failed: \(error.localizedDescription)")
        }
    }

    private func pinnedIPFromField(title: String) -> String? {
        guard let ip = sanitizedIPv4(pinnedField.stringValue) else {
            showMessage(title, "Enter a single IPv4 address like 128.14.14.141. Use the CIDR whitelist for network ranges.")
            return nil
        }
        return ip
    }

    @objc private func runPingCheck() {
        let host = sanitizedHost(pingHostField.stringValue)
        guard !host.isEmpty else { return }
        pingResultLabel.stringValue = "Pinging \(host)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand("/sbin/ping", ["-c", "3", host])
            let summary = pingSummary(host: host, result: result)
            DispatchQueue.main.async {
                self.pingResultLabel.stringValue = summary
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        if isAppLaunchLoaded() {
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", appLaunchAgentPath])
        } else {
            ensureAppLaunchAgentExists()
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", appLaunchAgentPath])
            _ = runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", appLaunchAgentPath])
            _ = runCommand("/bin/launchctl", ["enable", "gui/\(getuid())/\(appLaunchAgentLabel)"])
        }
        refreshAll()
    }

    @objc private func toggleAutoRestore() {
        if isAutoRestoreLoaded() {
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
        } else {
            ensureBridgeLaunchAgentExists()
            _ = runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", launchAgentPath])
            _ = runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", launchAgentPath])
            _ = runCommand("/bin/launchctl", ["enable", "gui/\(getuid())/\(launchAgentLabel)"])
        }
        refreshAll()
    }

    private func ensureAppLaunchAgentExists() {
        let executable = "\(NSHomeDirectory())/Applications/TailGateway.app/Contents/MacOS/TailGateway"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(appLaunchAgentLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executable)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
          <key>StandardOutPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.launchd.out.log</string>
          <key>StandardErrorPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.launchd.err.log</string>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(atPath: URL(fileURLWithPath: appLaunchAgentPath).deletingLastPathComponent().path, withIntermediateDirectories: true)
        try? plist.write(toFile: appLaunchAgentPath, atomically: true, encoding: .utf8)
    }

    private func ensureBridgeLaunchAgentExists() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(launchAgentLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(tailGatewayAutoPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.restore.launchd.out.log</string>
          <key>StandardErrorPath</key>
          <string>\(NSHomeDirectory())/Library/Logs/TailGateway.restore.launchd.err.log</string>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(atPath: URL(fileURLWithPath: launchAgentPath).deletingLastPathComponent().path, withIntermediateDirectories: true)
        try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
    }

    private func isAppLaunchLoaded() -> Bool {
        runCommand("/bin/launchctl", ["print", "gui/\(getuid())/\(appLaunchAgentLabel)"]).code == 0
    }

    private func isAutoRestoreLoaded() -> Bool {
        runCommand("/bin/launchctl", ["print", "gui/\(getuid())/\(launchAgentLabel)"]).code == 0
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === pinnedTableView {
            return pinnedEntries.count
        }
        return domainEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isPinnedTable = tableView === pinnedTableView
        let entries = isPinnedTable ? pinnedEntries : domainEntries
        let identifier = NSUserInterfaceItemIdentifier(isPinnedTable ? "pinnedCell" : "domainCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        if cell.identifier == nil {
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = entries[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedTable = notification.object as? NSTableView else { return }
        if selectedTable === pinnedTableView {
            let row = pinnedTableView.selectedRow
            guard row >= 0 && row < pinnedEntries.count else { return }
            pinnedField.stringValue = pinnedEntries[row]
        }
    }

    private func showResult(_ title: String, _ result: CommandResult) {
        let message = result.output.isEmpty ? "Exit code: \(result.code)" : result.output
        showMessage(title, message)
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = TailGatewayApp()
app.delegate = delegate
app.run()
