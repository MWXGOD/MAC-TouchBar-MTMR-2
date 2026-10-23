# MTMR-2：网易云音乐 Touch Bar 歌词与控制

MTMR-2 是一款面向网易云音乐 macOS 客户端的原生 Touch Bar 工具。它会在切换应用时继续显示居中的当前歌词，并提供上一首、播放/暂停、下一首控制；macOS 原生 Control Strip 仍可正常使用。

当前发布版本：**v2.1.1**。

仓库包含应用源码、歌词后台代理、安装与构建脚本、诊断工具，以及可直接使用的 Apple Silicon 版本 `MTMR-2.app`。

## 功能

- **居中显示歌词**：只显示当前歌词行，不显示歌名和歌手。歌词时间跟随播放器的 MediaRemote 播放进度，不使用固定提前量。
- **网易云播放控制**：上一首、播放/暂停、下一首分别响应点击，但视觉上组成一个连续的圆角分段组件。每段尺寸为 `50×30` 点，保留当前白色图标和灰色背景样式。
- **只向网易云发送控制**：优先通过辅助功能操作网易云自己的控制菜单，不激活网易云窗口。命令会串行执行，并比对操作前后的播放状态；在适用情况下使用定向备用方式，不发送会误控 Apple Music 等其他播放器的通用媒体命令。
- **关闭后可恢复**：关闭 MTMR-2 歌词 Touch Bar 后，可通过原生 Control Strip 中的 MTMR 项目重新显示。
- **原生 Control Strip**：保留 macOS 系统控制栏，仍可按系统原有方式展开。
- **图标**：Touch Bar Control Strip 中使用白色 MTMR 图案；屏幕顶部菜单栏使用原版圆角图标。
- **屏幕休眠同步**：菜单栏选项“屏幕休眠时同步触控栏”默认开启。屏幕休眠时最小化 MTMR-2 的 Touch Bar，屏幕唤醒后恢复；设置会被记住。
- **按钮诊断日志**：记录触摸回调、采用的控制路径，以及播放状态是否发生预期变化，便于定位按钮无响应的原因。

## 环境要求

- 配备 Touch Bar 的 Mac，macOS 11 或更新版本。
- Apple Silicon：仓库内预编译 app 和依赖安装脚本面向 Apple Silicon。
- 网易云音乐 macOS 客户端，Bundle ID 为 `com.netease.163music`。
- 需要在 macOS“辅助功能”设置中允许 MTMR-2 控制网易云音乐。
- 从源码构建或安装歌词代理需要 Xcode Command Line Tools 和 Homebrew。

## 安装与运行

在仓库目录中准备 MediaRemote 读取工具并安装歌词后台代理：

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/install-launch-agent.sh
```

`install-dependencies.sh` 还会尝试通过 Homebrew 安装旧版 MTMR。使用仓库中的原生 `MTMR-2.app` 不需要旧版 MTMR preset；该 preset 是独立的兼容方案。

将预编译 app 安装到“应用程序”并启动：

```sh
ditto MTMR-2.app /Applications/MTMR-2.app
open /Applications/MTMR-2.app
```

首次启动时，在 macOS“系统设置 > 隐私与安全性 > 辅助功能”中允许 `/Applications/MTMR-2.app`。如果系统中保留了旧路径的 MTMR-2 授权，请移除旧项目，再添加“应用程序”目录中的版本。修改授权后，退出并重新启动 MTMR-2。

在网易云音乐中播放歌曲后，Touch Bar 会显示当前歌词和媒体按钮。安装脚本创建的后台代理会持续提供播放状态与歌词数据，因此请保留仓库目录；LaunchAgent 使用的是该目录下的 `build/touchbar-lyrics-agent`。

## 从源码构建

在 Apple Silicon Mac 上安装好 Xcode Command Line Tools 和 Homebrew 后运行：

```sh
./Scripts/install-dependencies.sh
./Scripts/build-agent.sh
./Scripts/build-native-touchbar.sh
open ./build/native-touchbar/MTMR-2.app
```

原生构建脚本会在需要时编译 HID helper，并把网易云 Touch Bar 图标和定向 AppleScript 备用脚本打包进 app。构建产物位于 `build/native-touchbar/MTMR-2.app`，采用本地 ad-hoc 签名。

GitHub 仓库中的 app 为 Apple Silicon（arm64）版本，未使用 Developer ID 签名或公证。首次下载后，macOS Gatekeeper 可能要求在 Finder 中通过右键菜单选择“打开”。

如需安装构建产物：

```sh
ditto ./build/native-touchbar/MTMR-2.app /Applications/MTMR-2.app
open /Applications/MTMR-2.app
```

## 测试与诊断

```sh
./Scripts/test-lrc.sh
python3 Tests/test_lrc.py
python3 Tests/test_agent.py
./Scripts/build-ax-probe.sh
./build/ax-touchbar-probe --bundle com.ahs.mtmr2 --depth 8 --json
```

歌词和播放状态保存在：

```text
~/Library/Application Support/TouchBarLyrics-MTMR-2/
```

常用文件：

- `display.txt`：当前 Touch Bar 显示的歌词；
- `state.json`：当前曲目及播放状态；
- `button-debug.log`：按钮回调、网易云命令路径和状态变化记录；
- `~/Library/Logs/touchbarlyrics-mtmr2.log`：歌词后台代理日志。

## 项目结构

- `Sources/NativeTouchBarController.m`：原生 Touch Bar、菜单栏图标和网易云控制逻辑；
- `Scripts/touchbar-lyrics-agent.py`：MediaRemote 状态读取与歌词后台代理；
- `Scripts/netease-media-command.applescript`：定向 UI 脚本备用控制方式；
- `Assets/netease-touchbar/`：高分辨率媒体按钮图标；
- `MTMR-2.app/`：预编译应用；
- `Tests/`：歌词解析与后台代理测试。

## 常见问题

- **按钮没有反应**：确认“辅助功能”中授权的是当前 `/Applications/MTMR-2.app`，然后退出并重启应用。查看 `button-debug.log` 判断按钮回调是否触发、控制命令是否成功。若使用 AppleScript 备用方式，还可能需要在“隐私与安全性 > 自动化”中允许 MTMR-2 控制 System Events。
- **歌词为空**：确认网易云音乐正在播放，并检查 `display.txt`、`state.json` 和 `~/Library/Logs/touchbarlyrics-mtmr2.log`。
- **Touch Bar 没有显示 MTMR-2**：确认设备配备 Touch Bar 后重新启动 MTMR-2。应用使用 macOS 私有的系统模态 Touch Bar API，该 API 可能随 macOS 版本变化。
- **歌词代理没有运行**：在仓库目录重新执行 `./Scripts/install-launch-agent.sh`，并查看后台代理日志。由于 LaunchAgent 引用当前仓库中的可执行文件，请勿移动或删除已安装代理所依赖的仓库目录。

`Scripts/install-mtmr-preset.sh` 用于安装独立的旧版 MTMR preset，运行仓库内原生 `MTMR-2.app` 不需要它。
