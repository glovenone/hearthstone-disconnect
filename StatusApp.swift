import AppKit
import Darwin
import Foundation

private let english: [String: String] = [
    "通过助手启动炉石": "Launch Hearthstone with plugin",
    "炉石正在运行，请先结束对局并退出游戏。": "Hearthstone is running. Finish your game and quit first.",
    "请先打开并登录 Battle.net，再通过助手启动炉石。": "Sign in to Battle.net, then launch Hearthstone from this helper.",
    "已启动炉石，正在等待插件心跳。": "Hearthstone launched. Waiting for plugin heartbeat.",
    "启动失败：请检查游戏文件、依赖与签名，查看助手日志。": "Launch failed. Check files, dependencies and signatures. See helper logs.",
    "插件未加载；结束对局并退出游戏后，请从助手菜单启动炉石。": "Plugin not loaded. Finish your game, quit, then launch from the helper.",
    "依赖不完整 · 查看日志": "Missing dependencies · See logs",
    "未加载 · 下次通过助手启动": "Not loaded · Use helper to launch",
    "启动入口待修复 · 查看日志": "Launcher needs repair · See logs",
    "游戏启动中 · 等待组件": "Starting · Waiting for plugin",
    "未收到组件心跳 · 查看日志": "No plugin heartbeat · See logs",
    "一键拔线": "Disconnect",
    "处理中…": "Working…",
    "正在发送指令…": "Sending request…",
    "已就绪 · 点击拔线": "Ready · Click to disconnect",
    "等待炉石启动": "Waiting for Hearthstone",
    "组件未加载 · 请重启游戏": "Not loaded · Restart game",
    "游戏内浮窗": "In-game overlay",
    "打开 Battle.net": "Open Battle.net",
    "退出拔线": "Quit Disconnect",
    "打开日志": "Open logs",
    "语言": "Language",
    "炉石：未运行": "Hearthstone: Not running",
    "炉石：运行中": "Hearthstone: Running",
    "拔线：就绪": "Plugin: Ready",
    "拔线：等待炉石启动": "Plugin: Waiting for Hearthstone",
    "拔线：启动入口待修复": "Plugin: Launcher needs repair",
    "拔线：本次未加载，下次启动生效": "Plugin: Restart game to load",
    "炉石拔线：点击模拟断线，右键打开菜单": "Click to disconnect; right-click for menu",
    "炉石拔线：未就绪，右键查看状态": "Not ready; right-click for status",
    "炉石未运行。": "Hearthstone is not running.",
    "拔线组件本次未加载；结束对局后重新启动炉石。": "Plugin not loaded. Restart Hearthstone after your game.",
    "拔线组件未加载；启动入口正在修复。": "Plugin not loaded. Repairing launcher.",
    "上一次请求仍在处理中。": "The previous request is still pending.",
    "无法发送拔线指令。": "Could not send request.",
    "已发送模拟断线指令。": "Disconnect request sent.",
    "当前没有可断开的对局连接。": "No game connection available.",
    "拔线调用失败，请查看游戏日志。": "Disconnect failed. Check game logs.",
    "炉石未回应拔线指令。": "Hearthstone did not respond."
]

private final class OverlayDragHandle: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 12, y: 9, width: 24, height: 3),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }
}

final class StatusApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let gameBundleID = "unity.Blizzard Entertainment.Hearthstone"
    private let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hearthstone Disconnect")
    private let gameExecutable = URL(fileURLWithPath:
        "/Applications/Hearthstone/Hearthstone.app/Contents/MacOS/Hearthstone")
    private var observedPID: pid_t?
    private var gameFirstSeen = Date.distantPast
    private let gameLauncher = GameLauncher(root: URL(fileURLWithPath: "/Applications/Hearthstone"))
    private var launchProcess: Process?
    private var launchItem: NSMenuItem!
    private var statusItem: NSStatusItem!
    private var gameItem: NSMenuItem!
    private var componentItem: NSMenuItem!
    private var overlayMenuItem: NSMenuItem!
    private var overlayPanel: NSPanel!
    private var overlayButton: NSButton!
    private var overlayStatus: NSTextField!
    private var feedbackUntil = Date.distantPast
    private var actionItem: NSMenuItem!
    private var language: String { UserDefaults.standard.string(forKey: "language") ?? "system" }
    private var effectiveLanguage: String {
        if language != "system" { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") { return "zh-Hant" }
        return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
    }
    private func text(_ value: String) -> String {
        if effectiveLanguage == "en" { return english[value] ?? value }
        if effectiveLanguage == "zh-Hant" {
            return value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? value
        }
        return value
    }
    private var statusTimer: Timer?
    private var responseTimer: Timer?
    private var pendingID: String?
    private var responseDeadline = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildOverlay()
        refreshStatus()
        statusTimer = Timer.scheduledTimer(timeInterval: 2, target: self,
            selector: #selector(refreshStatus), userInfo: nil, repeats: true)
        RunLoop.main.add(statusTimer!, forMode: .common)

        if !CommandLine.arguments.contains("--resident") {
            DispatchQueue.main.async { self.disconnect() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        disconnect()
        return false
    }

    private func buildStatusItem() {
        if statusItem != nil { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "炉石拔线")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.autoenablesItems = false
        gameItem = NSMenuItem(title: "炉石：未运行", action: nil, keyEquivalent: "")
        componentItem = NSMenuItem(title: "拔线：未加载", action: nil, keyEquivalent: "")
        gameItem.isEnabled = false
        componentItem.isEnabled = false
        menu.addItem(gameItem)
        menu.addItem(componentItem)
        menu.addItem(.separator())
        actionItem = menuItem(text("一键拔线"), action: #selector(disconnectFromMenu))
        menu.addItem(actionItem)
        overlayMenuItem = menuItem(text("游戏内浮窗"), action: #selector(toggleOverlay))
        overlayMenuItem.state = UserDefaults.standard.bool(forKey: "overlayDisabled") ? .off : .on
        menu.addItem(overlayMenuItem)
        launchItem = menuItem(text("通过助手启动炉石"), action: #selector(launchGame))
        menu.addItem(launchItem)
        menu.addItem(menuItem(text("打开 Battle.net"), action: #selector(openBattleNet)))
        menu.addItem(.separator())
        let languages = NSMenu()
        for (index, title) in ["跟随系统 / System", "简体中文", "繁體中文", "English"].enumerated() {
            let item = menuItem(title, action: #selector(changeLanguage(_:)))
            item.tag = index
            item.state = ["system", "zh-Hans", "zh-Hant", "en"][index] == language ? .on : .off
            languages.addItem(item)
        }
        let languageItem = NSMenuItem(title: text("语言"), action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        menu.addItem(languageItem)
        menu.addItem(menuItem(text("打开日志"), action: #selector(openLogs)))
        menu.addItem(menuItem(text("退出拔线"), action: #selector(quit)))
        statusItem.menu = nil
        self.menu = menu
    }

    private var menu: NSMenu?

    private func buildOverlay() {
        let size = NSSize(width: 196, height: 104)
        overlayPanel = NSPanel(contentRect: NSRect(origin: overlayOrigin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlayPanel.level = .statusBar
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = true
        overlayPanel.isMovableByWindowBackground = true
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.isReleasedWhenClosed = false

        let background = NSView(frame: NSRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor
        background.layer?.cornerRadius = 16
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        background.layer?.masksToBounds = true

        overlayButton = NSButton(frame: NSRect(x: 12, y: 34, width: 172, height: 44))
        overlayButton.isBordered = false
        overlayButton.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "模拟断线")?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .semibold))
        overlayButton.title = text("一键拔线")
        overlayButton.font = .systemFont(ofSize: 16, weight: .semibold)
        overlayButton.imagePosition = .imageLeading
        overlayButton.setAccessibilityLabel(text("一键拔线"))
        overlayButton.imageScaling = .scaleProportionallyDown
        overlayButton.toolTip = text("一键拔线")
        overlayButton.target = self
        overlayButton.action = #selector(disconnectFromMenu)
        background.addSubview(overlayButton)
        overlayStatus = NSTextField(labelWithString: text("等待炉石启动"))
        overlayStatus.frame = NSRect(x: 10, y: 12, width: 176, height: 18)
        overlayStatus.font = .systemFont(ofSize: 11, weight: .medium)
        overlayStatus.alignment = .center
        overlayStatus.textColor = .lightGray
        overlayStatus.lineBreakMode = .byTruncatingTail
        background.addSubview(overlayStatus)
        background.addSubview(OverlayDragHandle(frame: NSRect(x: 0, y: 80, width: 196, height: 24)))

        overlayPanel.contentView = background
        overlayPanel.delegate = self
    }

    private func overlayOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if let x = defaults.object(forKey: "overlayX") as? Double,
           let y = defaults.object(forKey: "overlayY") as? Double {
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) {
                return frame.origin
            }
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        return NSPoint(x: screen.visibleFrame.maxX - size.width - 12,
                       y: screen.visibleFrame.midY - size.height / 2)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, panel == overlayPanel else { return }
        UserDefaults.standard.set(Double(panel.frame.minX), forKey: "overlayX")
        UserDefaults.standard.set(Double(panel.frame.minY), forKey: "overlayY")
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp,
           let menu, let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        } else {
            disconnect()
        }
    }

    @objc private func refreshStatus() {
        let launcherInstalled = gameLauncher.available
        let gamePID = NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID)
            .first?.processIdentifier
        if observedPID != gamePID {
            observedPID = gamePID
            gameFirstSeen = Date()
            if pendingID != nil { finishRequest() }
        }
        let starting = gamePID != nil && Date().timeIntervalSince(gameFirstSeen) < 30
        let ready = gamePID.map { componentReady(for: $0) } ?? false

        gameItem.title = gamePID == nil ? "炉石：未运行" : "炉石：运行中"
        if ready {
            componentItem.title = "拔线：就绪"
        } else if gamePID == nil {
            componentItem.title = launcherInstalled ? "拔线：等待炉石启动" : "拔线：启动入口待修复"
        } else {
            componentItem.title = RuntimeCore.status(ready: false, gameRunning: true,
                starting: starting, launcher: launcherInstalled)
        }
        gameItem.title = text(gameItem.title)
        componentItem.title = text(componentItem.title)
        launchItem.isEnabled = gamePID == nil && launchProcess?.isRunning != true
        actionItem.isEnabled = ready && pendingID == nil
        overlayButton.isEnabled = ready && pendingID == nil
        overlayButton.attributedTitle = NSAttributedString(
            string: text(pendingID == nil ? "一键拔线" : "处理中…"),
            attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                         .foregroundColor: ready ? NSColor.white : NSColor.lightGray])
        if Date() >= feedbackUntil {
            overlayStatus.toolTip = nil
            overlayStatus.stringValue = text(pendingID != nil ? "正在发送指令…" : RuntimeCore.status(
                ready: ready, gameRunning: gamePID != nil, starting: starting, launcher: launcherInstalled))
        }
        statusItem.button?.contentTintColor = ready ? .systemGreen : .secondaryLabelColor
        overlayButton.contentTintColor = ready ? .systemGreen : .lightGray
        statusItem.button?.toolTip = text(ready ? "炉石拔线：点击模拟断线，右键打开菜单" : "炉石拔线：未就绪，右键查看状态")
        let gameIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == gameBundleID
        if (gameIsFrontmost || CommandLine.arguments.contains("--preview")) && overlayMenuItem.state == .on {
            overlayPanel.orderFrontRegardless()
        } else {
            overlayPanel.orderOut(nil)
        }
    }

    private func componentReady(for gamePID: pid_t) -> Bool {
        let heartbeat = supportDirectory.appendingPathComponent("heartbeat")
        guard let content = try? String(contentsOf: heartbeat, encoding: .utf8) else { return false }
        return RuntimeCore.heartbeatReady(content, pid: gamePID, now: Date().timeIntervalSince1970)
    }

    @objc private func launchGame() {
        guard launchProcess?.isRunning != true,
              NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID).isEmpty else {
            notify("炉石正在运行，请先结束对局并退出游戏。")
            return
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "net.battle.app").isEmpty else {
            notify("请先打开并登录 Battle.net，再通过助手启动炉石。")
            return
        }
        guard let launcher = Bundle.main.url(forResource: "DisconnectLauncher", withExtension: nil) else { return }
        do {
            try gameLauncher.prepare(gameRunning: {
                !NSRunningApplication.runningApplications(withBundleIdentifier: self.gameBundleID).isEmpty
            }, trusted: isSignedHearthstone, sign: {
                self.runCodeSign(["--force", "--sign", "-", $0.path]) &&
                self.runCodeSign(["--verify", "--strict", $0.path])
            })
            let process = Process()
            process.executableURL = launcher
            // Battle.net must already be logged in. hs_beta is the China product;
            // the global product can be selected through the gameUID preference.
            process.arguments = ["-launch", "-uid", UserDefaults.standard.string(forKey: "gameUID") ?? "hs_beta"]
            var environment = ProcessInfo.processInfo.environment
            for key in Array(environment.keys) where key.hasPrefix("DOORSTOP_") || key.hasPrefix("DYLD_") {
                environment.removeValue(forKey: key)
            }
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    self?.recordLaunch("Game process exited with status \(process.terminationStatus)")
                    self?.refreshStatus()
                }
            }
            try process.run()
            recordLaunch("Launched game PID \(process.processIdentifier); waiting for protocol 2 heartbeat")
            launchProcess = process
            notify("已启动炉石，正在等待插件心跳。")
            refreshStatus()
        } catch {
            recordLaunch("Launch failed: " + String(describing: error))
            NSLog("Assistant launch failed: %@", String(describing: error))
            notify("启动失败：请检查游戏文件、依赖与签名，查看助手日志。")
        }
    }

    private func recordLaunch(_ message: String) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + message + "\n"
        let url = supportDirectory.appendingPathComponent("launcher.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data(line.utf8).write(to: url, options: .atomic)
        } else if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(line.utf8))
        }
    }

    private func isSignedHearthstone(_ executable: URL) -> Bool {
        runCodeSign(["--verify", "--ignore-resources",
            "-R=anchor apple generic and certificate leaf[subject.OU] = \"G847MC6JZ5\"",
            executable.path])
    }

    private func runCodeSign(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    @objc private func disconnectFromMenu() { disconnect() }

    @objc private func toggleOverlay() {
        overlayMenuItem.state = overlayMenuItem.state == .on ? .off : .on
        UserDefaults.standard.set(overlayMenuItem.state == .off, forKey: "overlayDisabled")
        refreshStatus()
    }

    private func disconnect() {
        guard let gamePID = NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID)
            .first?.processIdentifier else {
            notify("炉石未运行。")
            return
        }
        guard componentReady(for: gamePID) else {
            notify("插件未加载；结束对局并退出游戏后，请从助手菜单启动炉石。")
            return
        }
        guard pendingID == nil else {
            notify("上一次请求仍在处理中。")
            return
        }

        let request = supportDirectory.appendingPathComponent("request")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: request.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > 10 {
            try? FileManager.default.removeItem(at: request)
        }
        guard !FileManager.default.fileExists(atPath: request.path) else {
            notify("上一次请求仍在处理中。")
            return
        }

        let id = UUID().uuidString
        let temporary = supportDirectory.appendingPathComponent("request.\(id)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let expires = Date().addingTimeInterval(4).timeIntervalSince1970
            try Data(("\(id) \(gamePID) \(expires)\n").utf8).write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: request)
        } catch {
            notify("无法发送拔线指令。")
            return
        }

        pendingID = id
        refreshStatus()
        responseDeadline = Date().addingTimeInterval(4)
        responseTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
            selector: #selector(checkResponse), userInfo: nil, repeats: true)
        RunLoop.main.add(responseTimer!, forMode: .common)
    }

    @objc private func checkResponse() {
        guard let id = pendingID else { return }
        let response = supportDirectory.appendingPathComponent("response")
        if let value = try? String(contentsOf: response, encoding: .utf8) {
            if let result = RuntimeCore.response(value, requestID: id) {
                finishRequest()
                switch result {
                case "sent": notify("已发送模拟断线指令。")
                case "not-ready": notify("当前没有可断开的对局连接。")
                default: notify("拔线调用失败，请查看游戏日志。")
                }
                return
            }
        }
        if Date() >= responseDeadline {
            finishRequest()
            notify("炉石未回应拔线指令。")
        }
    }

    private func finishRequest() {
        responseTimer?.invalidate()
        responseTimer = nil
        if let id = pendingID {
            let request = supportDirectory.appendingPathComponent("request")
            if let value = try? String(contentsOf: request, encoding: .utf8),
               value.split(whereSeparator: \.isWhitespace).first == Substring(id) {
                try? FileManager.default.removeItem(at: request)
            }
        }
        pendingID = nil
        refreshStatus()
    }

    private func notify(_ message: String) {
        let message = text(message)
        feedbackUntil = Date().addingTimeInterval(5)
        overlayStatus.stringValue = message
        overlayStatus.toolTip = message
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = ["-e", "display notification \"\(escaped)\" with title \"Hearthstone Disconnect\""]
        try? process.run()
    }

    @objc private func openBattleNet() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Battle.net.app"))
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        UserDefaults.standard.set(["system", "zh-Hans", "zh-Hant", "en"][sender.tag], forKey: "language")
        buildStatusItem()
        overlayButton.setAccessibilityLabel(text("一键拔线"))
        overlayButton.toolTip = text("一键拔线")
        feedbackUntil = .distantPast
        refreshStatus()
    }

    @objc private func openLogs() {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(supportDirectory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishRequest()
        statusTimer?.invalidate()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct DisconnectApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = StatusApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
