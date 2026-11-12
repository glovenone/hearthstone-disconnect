import AppKit
import Darwin
import Foundation

private final class OverlayDragHandle: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: 20, y: 9, width: 24, height: 3),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }
}

final class StatusApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let gameBundleID = "unity.Blizzard Entertainment.Hearthstone"
    private let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hearthstone Disconnect")
    private let gameExecutable = URL(fileURLWithPath:
        "/Applications/Hearthstone/Hearthstone.app/Contents/MacOS/Hearthstone")
    private var launcherCandidate: (size: UInt64, modified: Date, firstSeen: Date)?
    private var statusItem: NSStatusItem!
    private var gameItem: NSMenuItem!
    private var componentItem: NSMenuItem!
    private var overlayMenuItem: NSMenuItem!
    private var overlayPanel: NSPanel!
    private var overlayButton: NSButton!
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

        if !CommandLine.arguments.contains("--resident") {
            DispatchQueue.main.async { self.disconnect() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        disconnect()
        return false
    }

    private func buildStatusItem() {
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
        menu.addItem(menuItem("模拟断线", action: #selector(disconnectFromMenu)))
        overlayMenuItem = menuItem("游戏内浮窗", action: #selector(toggleOverlay))
        overlayMenuItem.state = UserDefaults.standard.bool(forKey: "overlayDisabled") ? .off : .on
        menu.addItem(overlayMenuItem)
        menu.addItem(menuItem("打开 Battle.net", action: #selector(openBattleNet)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出拔线", action: #selector(quit)))
        statusItem.menu = nil
        self.menu = menu
    }

    private var menu: NSMenu?

    private func buildOverlay() {
        let size = NSSize(width: 64, height: 72)
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
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.90).cgColor
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        overlayButton = NSButton(frame: NSRect(x: 8, y: 4, width: 48, height: 48))
        overlayButton.isBordered = false
        overlayButton.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "模拟断线")?
            .withSymbolConfiguration(.init(pointSize: 27, weight: .semibold))
        overlayButton.imagePosition = .imageOnly
        overlayButton.imageScaling = .scaleProportionallyDown
        overlayButton.toolTip = "模拟断线"
        overlayButton.target = self
        overlayButton.action = #selector(disconnectFromMenu)
        background.addSubview(overlayButton)
        background.addSubview(OverlayDragHandle(frame: NSRect(x: 0, y: 52, width: 64, height: 20)))

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
        let launcherInstalled = ensureLauncherInstalled()
        let gamePID = NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID)
            .first?.processIdentifier
        let ready = gamePID.map { componentReady(for: $0) } ?? false

        gameItem.title = gamePID == nil ? "炉石：未运行" : "炉石：运行中"
        if ready {
            componentItem.title = "拔线：就绪"
        } else if gamePID == nil {
            componentItem.title = launcherInstalled ? "拔线：等待炉石启动" : "拔线：启动入口待修复"
        } else {
            componentItem.title = launcherInstalled
                ? "拔线：本次未加载，下次启动生效"
                : "拔线：启动入口待修复"
        }
        statusItem.button?.contentTintColor = ready ? .systemGreen : .secondaryLabelColor
        overlayButton.contentTintColor = ready ? .systemGreen : .secondaryLabelColor
        statusItem.button?.toolTip = ready
            ? "炉石拔线：点击模拟断线，右键打开菜单"
            : "炉石拔线：未就绪，右键查看状态"
        let gameIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == gameBundleID
        if gameIsFrontmost && overlayMenuItem.state == .on {
            overlayPanel.orderFrontRegardless()
        } else {
            overlayPanel.orderOut(nil)
        }
    }

    private func componentReady(for gamePID: pid_t) -> Bool {
        let heartbeat = supportDirectory.appendingPathComponent("heartbeat")
        guard let content = try? String(contentsOf: heartbeat, encoding: .utf8) else { return false }
        let fields = content.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2,
              let heartbeatPID = Int32(fields[0]), heartbeatPID == gamePID,
              let timestamp = TimeInterval(fields[1]) else { return false }
        let age = Date().timeIntervalSince1970 - timestamp
        return age >= -2 && age < 5
    }

    private func ensureLauncherInstalled() -> Bool {
        guard let launcher = Bundle.main.url(forResource: "DisconnectLauncher", withExtension: nil),
              FileManager.default.fileExists(atPath: gameExecutable.path) else { return false }
        if FileManager.default.contentsEqual(atPath: launcher.path, andPath: gameExecutable.path) {
            launcherCandidate = nil
            return true
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: gameExecutable.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return false }
        let now = Date()
        if launcherCandidate?.size != size || launcherCandidate?.modified != modified {
            launcherCandidate = (size, modified, now)
            return false
        }
        guard let candidate = launcherCandidate,
              now.timeIntervalSince(candidate.firstSeen) >= 4,
              isSignedHearthstone(gameExecutable) else { return false }

        let directory = gameExecutable.deletingLastPathComponent()
        let gameRoot = URL(fileURLWithPath: "/Applications/Hearthstone")
        let realExecutable = directory.appendingPathComponent("Hearthstone.real")
        let signedBackup = gameRoot.appendingPathComponent("Hearthstone.original")
        let id = UUID().uuidString
        let stagedSigned = gameRoot.appendingPathComponent("Hearthstone.original.\(id).tmp")
        let stagedReal = gameRoot.appendingPathComponent("Hearthstone.real.\(id).tmp")
        let stagedLauncher = directory.appendingPathComponent("Hearthstone.\(id).tmp")
        defer {
            try? FileManager.default.removeItem(at: stagedSigned)
            try? FileManager.default.removeItem(at: stagedReal)
            try? FileManager.default.removeItem(at: stagedLauncher)
        }
        do {
            try FileManager.default.copyItem(at: gameExecutable, to: stagedSigned)
            try FileManager.default.copyItem(at: gameExecutable, to: stagedReal)
            guard runCodeSign(["--force", "--sign", "-", stagedReal.path]),
                  runCodeSign(["--verify", "--strict", stagedReal.path]) else {
                throw NSError(domain: "HearthstoneDisconnect", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not sign game copy"])
            }
            try FileManager.default.copyItem(at: launcher, to: stagedLauncher)
            guard rename(stagedSigned.path, signedBackup.path) == 0,
                  rename(stagedReal.path, realExecutable.path) == 0,
                  rename(stagedLauncher.path, gameExecutable.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            launcherCandidate = nil
            return true
        } catch {
            NSLog("Could not restore Hearthstone launcher: %@", error.localizedDescription)
            return false
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
        process.standardOutput = Pipe()
        process.standardError = Pipe()
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
            notify(ensureLauncherInstalled()
                ? "拔线组件本次未加载；结束对局后重新启动炉石。"
                : "拔线组件未加载；启动入口正在修复。")
            return
        }
        guard pendingID == nil else {
            notify("上一次请求仍在处理中。")
            return
        }

        let request = supportDirectory.appendingPathComponent("request")
        guard !FileManager.default.fileExists(atPath: request.path) else {
            notify("上一次请求仍在处理中。")
            return
        }

        let id = UUID().uuidString
        let temporary = supportDirectory.appendingPathComponent("request.\(id)")
        do {
            try Data((id + "\n").utf8).write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: request)
        } catch {
            notify("无法发送拔线指令。")
            return
        }

        pendingID = id
        responseDeadline = Date().addingTimeInterval(4)
        responseTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
            selector: #selector(checkResponse), userInfo: nil, repeats: true)
    }

    @objc private func checkResponse() {
        guard let id = pendingID else { return }
        let response = supportDirectory.appendingPathComponent("response")
        if let value = try? String(contentsOf: response, encoding: .utf8) {
            let fields = value.split(whereSeparator: \.isWhitespace)
            if fields.count == 2, fields[0] == id {
                finishRequest()
                switch fields[1] {
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
        pendingID = nil
    }

    private func notify(_ message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = ["-e", "display notification \"\(escaped)\" with title \"炉石拔线\""]
        try? process.run()
    }

    @objc private func openBattleNet() {
        if let url = URL(string: "battlenet://wtcg") { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = StatusApp()
app.delegate = delegate
app.run()
