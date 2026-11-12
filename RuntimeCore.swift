import Foundation

// Pure decisions shared by the UI and regression tests.
enum RuntimeCore {
    static func heartbeatReady(_ value: String, pid: Int32, now: TimeInterval) -> Bool {
        let fields = value.split(whereSeparator: \.isWhitespace)
        guard fields.count == 3, fields[2] == "2", Int32(fields[0]) == pid,
              let timestamp = TimeInterval(fields[1]), timestamp.isFinite else { return false }
        let age = now - timestamp
        return age >= -2 && age < 5
    }

    static func status(ready: Bool, gameRunning: Bool, starting: Bool, launcher: Bool) -> String {
        if ready { return "已就绪 · 点击拔线" }
        if !launcher { return "启动入口待修复 · 查看日志" }
        if !gameRunning { return "等待炉石启动" }
        return starting ? "游戏启动中 · 等待组件" : "未收到组件心跳 · 查看日志"
    }

    static func response(_ value: String, requestID: String) -> String? {
        let fields = value.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[0] == requestID else { return nil }
        return String(fields[1])
    }
}
