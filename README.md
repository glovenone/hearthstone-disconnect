# 炉石一键拔线 · Hearthstone Disconnect

macOS 菜单栏与游戏浮窗助手，通过 BepInEx 插件调用炉石客户端的 `Network.SimulateUncleanDisconnectFromGameServer()`。左键菜单栏图标或点击浮窗发送请求，右键查看状态、切换浮窗或退出。

## 环境与构建

需要 macOS 12+、Xcode Command Line Tools、.NET 8 SDK、合法安装的炉石客户端，以及已配置的 BepInEx 5 / Doorstop。默认安装目录为 `/Applications/Hearthstone`。仓库不分发游戏文件、游戏程序集或第三方运行库。

```sh
./build.sh
```

产物为 `build/拔线.app` 和 `bin/Release/netstandard2.0/DisconnectOnly.dll`。应用使用本地 ad-hoc 签名，默认构建当前机器架构。

## 安装

先退出游戏并备份游戏目录。本项目面向已配置兼容 BepInEx / Doorstop 的环境，并非完整的一键安装包。需要以下依赖：

```text
/Applications/Hearthstone/
  libdoorstop.dylib
  BepInEx/core/BepInEx.Preloader.dll
  BepInEx/unstripped_corlib/
  BepInEx/plugins/DisconnectOnly.dll
```

1. 将构建出的 DLL 复制到上面的 plugins 目录。
2. 将 `build/拔线.app` 复制到 `/Applications/拔线.app`。
3. 启动助手，等待几秒完成入口检测，再通过 Battle.net 启动游戏：

```sh
open -a /Applications/拔线.app --args --resident
```

4. 右键菜单栏确认“拔线：就绪”，再点击浮窗或左键图标发送指令。

普通启动应用会尝试立即发送一次请求；`--resident` 只启动常驻助手。`local.hearthstone.disconnect-only.plist` 是可选登录启动模板，供放入 `~/Library/LaunchAgents/` 后使用 launchctl 管理。

## 实现与排查

C# 插件在 Unity 主线程轮询请求，每秒写心跳。Swift 助手校验游戏 PID 和最近 5 秒心跳，以 UUID 匹配响应，4 秒超时。通信目录为 `~/Library/Application Support/Hearthstone Disconnect/`。

C 启动器通过 Doorstop 加载 BepInEx，并执行 `Hearthstone.real`。助手检测游戏更新覆盖入口后，等待文件稳定并验证 Blizzard 签名，备份原文件、为运行副本本地签名，再恢复启动器。**运行助手会修改游戏启动文件。**

- “等待炉石启动”：入口已准备好，游戏未运行。
- “本次未加载，下次启动生效”：结束对局后退出并重启游戏。
- “启动入口待修复”：检查游戏目录权限和官方可执行文件签名。
- “就绪”：当前游戏 PID 有新鲜插件心跳。
- “已发送模拟断线指令”：客户端调用已返回，不代表服务器已确认断线或重连完成。

日志位于游戏目录 `BepInEx/LogOutput.log`。游戏更新可能改变 API 或加载兼容性。

卸载：退出助手和游戏，卸载可选 LaunchAgent，通过 Battle.net 扫描修复恢复官方入口，再按需删除插件和助手。

## 验证记录

2026-11-12，本机客户端 37.0.255790：Swift、C 检查通过；C# 和完整应用构建通过（一个 `System.Net.Http` 依赖版本警告）。此前游戏更新覆盖启动入口，运行现有助手后入口已恢复。历史日志使用 BepInEx 5.4.23.3、Unity 6000.3.11f1，曾记录插件成功加载。本次直接启动游戏也记录了 `Disconnect Only ready` 并产生新心跳；随后游戏在启动阶段报告 Service Locator failure 并退出，尚未确定原因。插件加载已验证，实际进对局及断线/重连效果尚未验证。

## 许可证

自有源码使用 MIT 许可证；第三方和游戏文件受各自许可约束，不随仓库分发。项目与 Blizzard 无隶属关系。

## v1.5 界面与语言

- 横向深色圆角浮窗，图标旁显示「一键拔线」，底部显示当前状态与操作反馈。
- 右键菜单栏 →「语言」：跟随系统 / 简体中文 / 繁體中文 / English，立即切换并保存。
- 处理中禁用重复操作；超时后清理本次请求，允许重试。旧的残留请求在十秒后可清理。
- 右键菜单新增「打开日志」。拖动浮窗顶部可调整位置。
- 开发预览：`open -a /Applications/拔线.app --args --resident --preview`，无需游戏即可查看浮窗；正常使用省略 `--preview`。
