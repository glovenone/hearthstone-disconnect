# 炉石一键拔线 · Hearthstone Disconnect

macOS 菜单栏与游戏浮窗助手，通过 BepInEx 插件调用炉石客户端的 `Network.SimulateUncleanDisconnectFromGameServer()`。浮窗显示「一键拔线」和插件状态；支持简体中文、繁體中文、English 与跟随系统。

## 重要：从助手启动游戏

**v1.7 起不再替换官方游戏启动入口。** 本机发现入口在再次启动时被恢复为官方程序，导致此前的启动器方案失效。普通 Battle.net 启动不会自动加载此插件。

1. 完成当前对局，退出炉石，保持 Battle.net 已登录。
2. 右键「拔线」菜单栏图标 → **通过助手启动炉石**。
3. 等待“已就绪 · 点击拔线”，再点击浮窗发送指令。

助手读取并验证官方程序签名，准备单独的 `Hearthstone.real` 本地签名副本，然后通过自带启动器设置干净的 Doorstop 环境运行副本。官方 `Hearthstone` 文件不会被替换。游戏运行期间禁止准备副本或启动第二个游戏。

当前默认产品参数为国服 `hs_beta`。国际服可设置：

```sh
defaults write local.hearthstone.disconnect-only gameUID -string wtcg
```

## 环境与构建

需要 macOS 12+、Xcode Command Line Tools、.NET 8 SDK、合法安装的炉石客户端，以及已配置的兼容 BepInEx 5 / Doorstop。默认目录 `/Applications/Hearthstone`，本项目不包含游戏文件或第三方运行库。

```sh
./build.sh
./Tests/run.sh
```

产物：`build/拔线.app`（当前架构、本地 ad-hoc 签名）和 `bin/Release/netstandard2.0/DisconnectOnly.dll`。

安装时退出旧助手，将 app 复制到 `/Applications/拔线.app`，将 DLL 放入游戏目录 `BepInEx/plugins/`。助手与插件必须一起更新，已经运行的游戏不会热加载新 DLL。

需要的依赖：

```text
/Applications/Hearthstone/
  libdoorstop.dylib
  BepInEx/core/BepInEx.Preloader.dll
  BepInEx/unstripped_corlib/mscorlib.dll
  BepInEx/plugins/DisconnectOnly.dll
```

启动常驻助手：

```sh
open -a /Applications/拔线.app --args --resident
```

普通启动或重新打开已运行的助手会尝试发送一次断线请求。开发界面预览增加 `--preview`。可选登录启动模板为 `local.hearthstone.disconnect-only.plist`。

## 状态、协议和日志

- 游戏启动初期显示等待组件；没有心跳时明确提示下次从助手启动。
- 只有最近 5 秒内、当前游戏 PID、协议版本 2 的心跳才允许发送请求。
- 请求包含 UUID、目标 PID 和 4 秒有效期。过期、跨进程和旧协议请求不会执行。
- 心跳与响应原子写入；处理中阻止重复操作，超时和退出时清理自身请求。
- “指令已发送”表示客户端方法返回，并非服务器确认断线或重连。

右键“打开日志”进入 `~/Library/Application Support/Hearthstone Disconnect/`，其中 `launcher.log` 记录启动错误和退出状态；目录也包含心跳和通信文件。插件日志仍在游戏目录 `BepInEx/LogOutput.log`。

本机此前使用 BepInEx 5.4.23.3、Unity 6000.3.11f1、客户端 37.0.255790。更新可能改变兼容性。构建仍有一个 System.Net.Http 依赖版本冲突警告。

## 验证边界

v1.7 已通过 55 项 Swift/C# 断言和 C 启动器回归测试，实际游戏文件的临时副本也通过签名准备检查。**新入口的真实登录、插件加载和对局断线重连尚未验证**；用户对局期间未退出或重启游戏。此前的 [v1.6 检查记录](docs/stability-review-2026-11-12.md) 描述旧入口方案，已由 v1.7 替代。

卸载时退出助手，删除可选 LaunchAgent、插件、助手和副本。如曾使用旧版替换入口，通过 Battle.net 扫描修复恢复官方程序。

## 许可证

自有源码采用 MIT；游戏和第三方组件遵循各自许可，不随仓库分发。与 Blizzard 无隶属关系。
