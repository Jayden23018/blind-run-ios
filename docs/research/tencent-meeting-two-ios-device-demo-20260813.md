# 腾讯会议上同屏演示两台 iOS 真机：可行方案与已知坑

**日期**：2026-08-13
**动机**：需要在腾讯会议上向导师演示「盲人下单 → 志愿者接单」完整链路。本仓库的 App
**永远不能跑模拟器**（高德 SDK 无 arm64-sim slice，见 `CLAUDE.md`），因此两个角色必须落在
两台真机上，问题变成「怎么把两台真机的画面同时送进腾讯会议的共享流」。
**本机实测环境**：macOS 26.5.2（25F84）、腾讯会议 3.41.1、iPhone 16 Pro + iPad Air 5（均已配对）。

---

## 结论（一句话）

腾讯会议**没有**「手机投屏作为共享源」的能力；标准做法是先用 **QuickTime Player 影片录制**
把两台设备各镜像成一个 Mac 窗口，再让腾讯会议共享这两个窗口（3.30+ 支持 Shift 多选）
或直接共享整个桌面。**QuickTime 镜像有会中断线的已知 bug，必须准备录屏备胎。**

---

## 1. 腾讯会议侧能做什么（官方文档核实）

来源：[腾讯会议帮助中心 · 共享屏幕使用指南](https://meeting.tencent.com/support/topic/1633/index.html)（2026-08-13 核实）

| 能力 | 结论 | 原文依据 |
|---|---|---|
| 共享整个桌面 / 单个窗口 | ✅ 支持 | 「会中点击底部工具栏【共享屏幕】-> 选择共享内容，并点击【开始共享】」 |
| **同时共享多个应用窗口** | ✅ **3.30 及以上**版本支持 | macOS 需「按住『Shift』键，并选择需要共享的应用」；所选内容四周出现绿色边框 |
| 手机投屏当共享源 | ❌ **文档中未提及，不支持** | 移动端共享的是设备自身屏幕，不能投到桌面端当共享源 |
| 同时共享电脑声音 | ✅ 支持 | 「将窗口/桌面/白板内容共享的同时，把电脑本身发出的声音也一并进行共享」 |

> 本机装的是 **3.41.1**，≥ 3.30，多窗口共享可用。

腾讯会议另有一套「本地投屏 / Rooms 无线投屏 / 超声波投屏」
（[目录](https://meeting.tencent.com/support/topic/1226/)），但那是把画面投到**会议室硬件终端**的场景，
需要 Rooms 设备或 NP30 配件，**与「远程会议里共享手机画面」是两回事**，不适用。

## 2. 把 iOS 设备镜像进 Mac 的两条路

### 2a. QuickTime Player + USB（首选）

标准流程：QuickTime Player → `File > New Movie Recording`（⌘⌥N）→ USB 连接设备 →
点录制键旁的下拉箭头 → 在 **Screen** 分类下选择该设备。麦克风/扬声器可另外单独选。

**两台设备同时镜像是可行的**：每台设备各占一个「影片录制」窗口 —— 开第一个窗口指到设备 A，
再按一次 ⌘⌥N 开第二个窗口指到设备 B，两个窗口可自由缩放并排摆放。
只镜像不录制时，把鼠标移开窗口，录制控件会自动隐藏。
来源：[MacSales · Tech 101: How to Mirror More Than One iOS Device to a Mac or PC](https://eshop.macsales.com/blog/43966-tech-101-how-to-mirror-more-than-one-ios-device-to-a-mac-or-pc/)、
[BigBlueButton 支持文档](https://support.blindsidenetworks.com/hc/en-us/articles/4407788663309-How-to-mirror-your-iPad-iPhone-screen-to-a-Mac-computer-with-QuickTime)

**限制与坑**：

- Mac 的键鼠**不能**反向操作 iOS 设备，只能看 —— 演示时手要放在真机上操作。
- 连上后 Photos / 音乐 App 可能自动弹出，先关掉。
- 设备没出现在列表里：拔掉重插。
- ⚠️ **已知 bug（多个 Apple 社区帖复现）**：镜像会在会话中途停止，设备从 Screen 源列表里
  消失（Camera 源仍在），换线、换设备都无效，**只有重启 Mac 能恢复**。
  来源：[Apple Community 254405459](https://discussions.apple.com/thread/254405459)、
  [255804734](https://discussions.apple.com/thread/255804734)、
  [255038067](https://discussions.apple.com/thread/255038067)
  → **对直播演示这是真实风险，必须准备录屏备胎。**

### 2b. AirPlay 到 Mac（备选 / 第二台设备的退路）

macOS 12 Monterey 起内置「隔空播放接收器」，iPhone/iPad（iOS 15+）可无线镜像到 Mac；
**也支持 USB 有线 AirPlay**（无 Wi-Fi 或要求零延迟时用）。
macOS 13+ 开启路径：系统设置 → 通用 → 隔空投送与接力 → 打开「隔空播放接收器」。
iPhone 侧：控制中心 → 屏幕镜像 → 选 Mac。
**最常见的失败原因是 Mac 侧没开接收器开关**（与投 Apple TV 不同，Mac 必须显式打开）。
来源：[Apple 官方 · Continuity features and requirements](https://support.apple.com/en-us/108046)、
[MacSales · How to Use Airplay to Mac in macOS Monterey](https://eshop.macsales.com/blog/78537-how-to-use-airplay-to-mac-in-macos-monterey/)

本机 macOS 26.5.2 远超 12.0 门槛，可用。早期版本 AirPlay 镜像是全屏独占、窗口不可调，
新版已改善 —— 但**两台设备同时 AirPlay 到同一台 Mac 不被支持**，所以它只能当
「QuickTime 挂了之后救其中一台」的退路，不能替代主方案。

## 2c. ⛔ iPhone 镜像（iPhone Mirroring）：语音演示下**绝对不能用**

**这是与 §2a 完全不同的机制，极易混淆，务必分清。**「iPhone 镜像」是 macOS Sequoia 起的
连续互通功能（在 Mac 上反向控制 iPhone）；QuickTime「影片录制」是把设备当采集源。

**致命限制：iPhone 镜像会话期间 iPhone 必须保持锁定，因此摄像头、麦克风、Face ID
全部不可用。** 这是 Apple 的设计而非 bug，无绕法 —— 语音听写、语音消息、通话、
相机类功能在镜像会话里一律不工作。iPhone 若处于解锁状态，镜像要么连不上、
要么自动暂停。音频**输出**方向是通的（iPhone 播的声音会从 Mac 出），但**输入**方向不通。
来源：[MacRumors · iPhone Mirroring 完全指南](https://www.macrumors.com/guide/iphone-mirroring/)（2026-08-13 核实）

> **AidRun 盲人端的核心演示是语音下单，需要 App 实时占用麦克风，两个方向都要 ——
> 所以 iPhone 镜像对本项目直接出局。**

其它限制：看不到控制中心/通知中心/锁屏；DRM 内容不能播；欧盟因 DMA 不可用；
要求 macOS 15 + iOS 18、同一 Wi-Fi、蓝牙开启、无进行中的 AirPlay / 热点 / 随航会话。

## 2d. QuickTime 镜像时音频怎么配（语音演示的关键）

QuickTime 的 **Camera（画面源）** 与 **Microphone（音频源）** 是两个独立下拉项。

- **Camera / Screen 选 iPhone** —— 画面源，必选。
- **Microphone 选「无」或 Mac 自带麦克风，不要选 iPhone。**
  选成 iPhone 会劫持音频路由：它把 iPhone 的音频**输出**灌进 Mac 的音频输入，
  有用户报告因此在通话里听不到声音（内容仍被录下）。
  来源：[Apple Community 254563291](https://discussions.apple.com/thread/254563291)、
  [OSXDaily · Record iPhone Screen with QuickTime](https://osxdaily.com/2016/02/15/howto-record-iphone-screen-mac-quicktime/)

**推荐的最简配置（零额外软件）**：QuickTime Microphone 设为「无」，iPhone 的 TTS 从
它自己的扬声器放出来，手机放在 Mac 麦克风旁边，腾讯会议用 **Mac 麦克风**同时收
「你的讲解 + 手机的播报」。音质一般，但环节最少、直播时最不容易炸。

**不推荐**为此装 BlackHole / Loopback 建聚合设备 + 多输出设备把系统音回环 ——
QuickTime 本身没有系统音采集通道，要做就得搭一整套虚拟音频设备，
演示前一天引入这套东西风险大于收益。

> ⚠️ **一个未核实项，只能实测**：QuickTime 采集 iOS 屏幕时是否会与 App 自身的
> `AVAudioSession`（语音识别要独占麦克风）冲突 —— 官方文档没写，社区也无可信记载。
> 插线、开 QuickTime、真跑一次语音下单，确认识别正常且能听见播报。
> 本仓库记忆 `audio-correctness-needs-real-ears-not-code-reading` 说的正是这类问题：
> 调用点全对也可能一声不响，只能用耳朵验。

## 2e. 设备不出现在 QuickTime 列表里 —— 排查顺序与**两个会骗人的检查**

**2026-08-13 本机实测，排查过程本身踩了两个坑，两个都会让你得出反向结论。**

### ⛔ 坑 1：`system_profiler SPUSBDataType` 会静默返回空

这条命令在本机（macOS 26.5.2 + Claude Code 沙箱）**returncode = 0、stdout = 0 字节**，
既不报错也不提示。据此判「USB 上没有 iOS 设备」是**假阴性** —— 实际设备好好连着。
判 USB 连接**不要用它**，用下面两条之一：

```bash
# ① 看 USB 树上有没有 IOUSBHostDevice 节点
ioreg -p IOUSB -w 0 -l | grep -E '\+-o (iPhone|iPad)'

# ② 直接问 devicectl 传输方式（最权威，一眼看到 wired / wireless）
xcrun devicectl device info details --device <UDID> --quiet --json-output /tmp/d.json
python3 -c "import json;d=json.load(open('/tmp/d.json'));import re;print(re.findall(r'\"transportType\"\s*:\s*\"[^\"]*\"',json.dumps(d)))"
```

`transportType = "wired"` + `pairingState = "paired"` 才算「线和信任都通了」。
⚠️ `xcrun devicectl list devices` 的 `available (paired)` **不含传输方式信息**，
它对无线配对的设备也显示 available，不能拿来判有线。

### ⛔ 坑 2：命令行 Swift 枚举 `AVCaptureDevice` 也可能是假阴性

用未签名的 `swift xxx.swift` 枚举采集设备时，`AVMediaType.muxed`（iOS 屏幕采集设备所在的
类别）返回 0 个，而同一次枚举**能**列出连续互通相机与各路麦克风。未签名 CLI 拿不拿得到
完整设备列表没有可信记载，**因此「muxed 为空」不能证明 QuickTime 也看不到**。
权威判据只有 QuickTime 本身。

> 顺带一个真实存在、值得知道的区分：枚举里出现的 `xxx's iPhone Camera`
> （`AVCaptureDeviceTypeExternal`、`isContinuityCamera = true`）是**连续互通相机**——
> 无线的、拍的是**摄像头画面**，不是手机屏幕。误选它就会看到"直接调用了摄像头"。

### macOS 26 没有移除这个功能

Apple 的 QuickTime Player 用户指南在 macOS Tahoe 26 上仍然写着
`File > New Movie Recording` → 在 **Camera** 下选择已连接的 iPhone / iPad。
社区反馈是**画质下降**（无 4K、压缩变重）和**长时间录制中途停止**，不是功能移除。
来源：[Apple 支持 · Record a movie in QuickTime Player](https://support.apple.com/guide/quicktime-player/record-a-movie-qtp356b55534/mac)、
[Apple Community 256154125](https://discussions.apple.com/thread/256154125)、
[256183321](https://discussions.apple.com/thread/256183321)

### 已排除但值得先查的一项：iPhone 镜像正在运行

`iPhone Mirroring.app` **强制手机保持锁定**（见 §2c），运行期间会占着设备。
查 + 退：

```bash
ps -Axo comm | grep -i "iPhone Mirroring"
osascript -e 'quit app "iPhone Mirroring"'
```

（本次实测退掉后 muxed 仍为 0，但受坑 2 影响该结论不作数，仍建议先退。）

**菜单位置的准确说法**（此前本文写成「Screen」，不完全对）：
`文件 > 新建影片录制`（**不是**「新建屏幕录制」，后者录的是 Mac 桌面）→ 点录制键
**旁边的下拉箭头** → 设备出现在 **Camera / 摄像头**分组下；较新系统还会另有一个
独立的 **Screen / 屏幕**分组。老版 iOS 上曾出现过只显示「iPhone Camera」（真的是相机画面、
不是屏幕）的情况，升级 iOS 后才出现 Screen 分组。
来源：[Apple 支持 · QuickTime Player 录制影片](https://support.apple.com/en-lb/guide/quicktime-player/qtp356b55534/mac)、
[Apple Community 255406835](https://discussions.apple.com/thread/255406835)

**其余排查顺序**（按命中率）：

1. **手机解锁并让屏幕常亮** —— 锁着屏时屏幕采集设备不发布，这是最容易忽略的一条
2. **完全退出 QuickTime（⌘Q）再重开** —— 它在启动时枚举设备，插线晚于开 App 就看不到
3. 退掉 `iPhone Mirroring.app`（见上）
4. 用**数据线**、直插 Mac 不经 hub；换个口试
5. 弹出「信任此电脑」要点**信任**并输密码；误点过「不信任」→ iPhone 设置 → 通用 →
   传输或还原 → 还原 → **还原位置与隐私**，重插再点信任
6. 重启 iPhone（社区反馈命中率不低）
7. 退掉会抢摄像头/麦克风的工具（Micro Snitch 一类）

> **Finder 能看到 ≠ QuickTime 能看到。** Finder 在「在 Wi-Fi 下显示此 iPhone」开启时
> 也会列出无线设备，且它用的是另一条通道，与屏幕采集设备是否发布无关。
> 不要拿 Finder 当 QuickTime 的前置判据（本文上一版这么写过，是错的）。

## 3. 被否掉的方案

| 方案 | 为什么否 |
|---|---|
| 两台设备各自加入腾讯会议并共享自己屏幕 | 腾讯会议默认同一时刻只允许一个共享者；且两台设备入会会引入回声，还要各自占一路上行带宽 |
| 用腾讯会议的「本地投屏 / Rooms 投屏」 | 需要 Rooms 硬件终端或 NP30 配件，是会议室场景，不是远程会议共享 |
| 跑模拟器省掉一台真机 | 本仓库硬约束：高德 SDK 无 arm64-sim slice，模拟器通道**永久不可用** |
| **iPhone 镜像（iPhone Mirroring）** | **镜像期间 iPhone 必须锁定 → 麦克风不可用 → 语音下单跑不起来。见 §2c，无绕法** |
| 第三方投屏软件（AirServer / Reflector 等） | 知乎上有人这么解决，但均为付费闭源、要装内核外的采集组件，演示前一天引入新变量不划算 |

---

## 复核触发条件

- 腾讯会议大版本更新（尤其若新增「移动设备作为共享源」能力，则 §1 结论作废）
- macOS 大版本更新改变 QuickTime 设备捕获行为，或 Apple 修掉 §2a 的镜像中断 bug
- Apple 放开 iPhone 镜像的锁定要求或开放麦克风（则 §2c 的出局理由作废）
- §2d 末尾那条「QuickTime 采集是否抢 App 麦克风」实测出结论后，回来把它从未核实改成定论
- 换演示设备组合（例如改成两台 iPhone，或引入 Apple Silicon 以外的 Mac）
