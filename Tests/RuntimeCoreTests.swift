import Foundation
@main struct RuntimeCoreTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool) { precondition(condition); checks += 1 }
        check(RuntimeCore.heartbeatReady("42 1000 2", pid: 42, now: 1001))
        for value in ["", "42", "42 garbage 2", "42 nan 2", "42 inf 2", "41 1000 2", "42 990 2", "42 1010 2", "42 1000 extra", "42 1000", "42 1000 1"] {
            check(!RuntimeCore.heartbeatReady(value, pid: 42, now: 1001))
        }
        check(!RuntimeCore.heartbeatReady("42 1000 2", pid: 42, now: 1005))
        check(RuntimeCore.status(ready: false, gameRunning: true, starting: true, launcher: true) == "游戏启动中 · 等待组件")
        check(RuntimeCore.status(ready: false, gameRunning: true, starting: false, launcher: true) == "未收到组件心跳 · 查看日志")
        check(RuntimeCore.status(ready: false, gameRunning: false, starting: false, launcher: false) == "启动入口待修复 · 查看日志")
        check(RuntimeCore.status(ready: true, gameRunning: true, starting: false, launcher: true) == "已就绪 · 点击拔线")
        check(RuntimeCore.response("old sent", requestID: "new") == nil)
        check(RuntimeCore.response("new sent extra", requestID: "new") == nil)
        check(RuntimeCore.response("new sent", requestID: "new") == "sent")
        print("PASS: \(checks) runtime assertions")
    }
}
