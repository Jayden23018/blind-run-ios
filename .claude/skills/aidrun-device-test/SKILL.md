---
name: aidrun-device-test
description: AidRun 真机跑测（scripts/device-test.sh）的跑前检查、签名团队判定与失败分诊。要在真机跑单测 / UI 测试、device-test.sh 报错（签名、No Account for Team、code 74、证书不受信任、免费 App 数量上限、锁屏）、或换了开发者团队 / 换了 Mac / 换了设备时读。
---

# AidRun 真机跑测

真机是本仓库**唯一**的 XCTest 通道（高德无 arm64-sim slice，模拟器永久不可用）。
跑多大范围（只跑改动覆盖的 suite）见 skill `aidrun-ship-check` §六，这里不重复。

> ⛔ **本文件不写任何具体的团队号、设备号、bundle id。** 它们都会变（2026-10-03 一天之内换过团队），
> 每一项都给出「当场怎么查」。看到下面的 `<尖括号>` 就去跑旁边那条命令。

## 一、跑前四查（每次都查，都是一条命令）

1. **Xcode 图形界面必须退出**（⌘Q，关窗口不够）。脚本第 0.6 节会拦，确需开着用 `AIDRUN_ALLOW_XCODE_OPEN=1`。
   不退出时 UI 测试的 runner 握手被拒，报 code 74，看起来像没插线。
2. **设备连着、走 USB、已解锁**：
   ```bash
   xcrun devicectl list devices                     # 状态要是 connected，不是 unavailable
   xcrun xctrace list devices | grep -v Simulator   # 括号里那串是硬件 UDID
   ```
   硬件 UDID 和 `scripts/device-test.sh` 里 `DEVICE_ID` 的默认值不一样时，用 `AIDRUN_DEVICE_ID=<硬件 UDID>` 覆盖。
   ⚠️ `devicectl` 那列 Identifier（8-4-4-4-12 的 UUID 形状）**不是**硬件 UDID，传给 `AIDRUN_DEVICE_ID` 会报「Unable to find a device」；
   它只用于 `devicectl` 自己的命令（例如第三节的列 App / 卸载）。
3. **工作区初始化过**：`LocalConfig.xcconfig` 与 `Pods/` 都在（脚本第 0.5 节会拦，并告诉你怎么补）。
4. **签名团队判定** —— 见第二节。

## 二、用哪个团队签名

先查两样东西：

```bash
# 工程要的团队（当前值，别背）
grep -m1 'DEVELOPMENT_TEAM = ' blindRun.xcodeproj/project.pbxproj
# 本机 Xcode 登录的账号能看到哪些团队
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -E 'teamID|teamName|teamType'
```

- **工程团队在列表里** ⇒ 直接 `scripts/device-test.sh -only-testing:…`，不传任何覆盖。
- **不在列表里**（Xcode 签名页 Team 栏是红字 `Unknown Name (<团队号>)`）⇒ 你不是那个团队的开发成员。
  重新登录、换账号都没用 —— 若那是**个人类型**开发者账号，加进来的成员（哪怕 Admin）只有 App Store Connect 权限，
  拿不到开发权限（苹果原文与出路见 `docs/research/individual-team-cannot-sign-for-members-20261004.md`）。
  改用**自己的免费个人团队**：

  ```bash
  AIDRUN_TEAM=<上面列表里 teamType = Personal Team 的 teamID> \
  AIDRUN_BUNDLE_ID_PREFIX=<一个只属于你的反向域名，例如 com.<你的名字>.aidrun> \
  scripts/device-test.sh -only-testing:…
  ```

  - 前缀要**每人一个、一直用同一个**：bundle id 全球唯一，别人团队注册过的你用不了；换前缀会多占免费团队「每 7 天 10 个 App ID」的额度。
    查自己以前用过哪个：`ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/`，逐个
    `security cms -D -i <文件> | grep -A1 application-identifier`，形如 `<你的团队号>.<前缀>`。
  - 设了前缀，脚本会同时清空 `CODE_SIGN_ENTITLEMENTS`：免费团队不支持推送能力，带着它签名直接失败。
    所以**推送相关的行为在免费团队下验不了**，要验只能在工程团队成员的 Mac 上跑。
  - 当前分支的 pbxproj 里 bundle id 还是写死的（没有 `$(AIDRUN_BUNDLE_ID_PREFIX:default=…)`）⇒ 前缀覆盖不生效。
    这时开一个临时 worktree：`git worktree add --detach /tmp/<名字> <分支>`，在里面 cherry-pick 那条覆盖提交再跑，
    **跑完删掉 worktree，不推送** —— 别把它混进当前分支的 PR。

⛔ **别在 Xcode 签名页改 Team 并保存。** Xcode 会直接把 `DEVELOPMENT_TEAM` 写进 pbxproj，
提交上去会让工程团队那边上传 TestFlight 签名失败。本地跑测只用上面的环境变量。
提交前 `git status` 里出现 pbxproj / `.xcscheme`、而本次改动不涉及它们 ⇒ 是打开 Xcode 带出来的，
备份 diff 后用 `AIDRUN_ALLOW_DISCARD=1 git checkout -- <这些文件>` 还原。

## 三、第一次用某个证书时，手机上要人点的两件事

| 现象 | 要谁做什么 |
|---|---|
| `Developer App Certificate is not trusted` | 用户在 iPhone：设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任 |
| `maximum number of installed apps using a free developer profile` | 免费 profile 的 App 每台设备最多 3 个，UI 测试还要多装一个 runner。列出来：`xcrun devicectl device info apps --device <devicectl 的 Identifier>`，**先问用户**再 `xcrun devicectl device uninstall app --device <…> <bundle id>`（会清掉那个 App 在手机上的数据） |

## 四、读结果

- 只认脚本最后那行 `passed=N failed=M`（来自 result bundle）。**`passed=0` 一律当失败**。
- 「套件绿」不等于「新用例跑过」：脚本会打印 `日志：<路径>`，在那份 xcodebuild 日志里逐个 grep 新用例名，确认是 `passed`。
- `failed=1 total=1` 且那一条叫 `blindRun` / `blindRunUITests-Runner` ⇒ 是安装 / 启动失败，**一条用例都没跑**，不能说「测试失败」。

## 五、失败签名速查（细节与历次现场在记忆 `ui-test-runner-needs-usb-not-wifi`）

| 报错里的关键句 | 先做什么 |
|---|---|
| `No Account for Team "<团队号>"` / Team 栏 `Unknown Name` | 第二节：改用自己的免费个人团队 |
| `No Accounts` | 用户在 Xcode → Settings → Accounts 登录 Apple ID（我不碰凭据） |
| `Developer App Certificate is not trusted` | 第三节：手机上信任证书 |
| `maximum number of installed apps using a free developer profile` | 第三节：问用户后卸载旧的免费 App |
| `exited with code 74 before establishing connection` | 先 `pgrep -x Xcode`；开着就请用户 ⌘Q。再回原始日志 grep `refused\|Exiting due`。都不是再查 USB（`transportType` 要是 `wired`） |
| `设备处于锁屏状态` | 用户解锁，并把自动锁定设成「永不」 |
| `日志连续 Ns 没有新输出、也没开始跑用例` | 编译期间不计时（2026-10-05 起），所以这一句**就是**卡住：看 `devicectl` 的 `transportType` 是不是 `wired`、手机解没解锁 |
| `Failed to create directory on device … runtime profiles`（bundle id 是默认的 `com.culiu-tech…` 也照样） | **原样复跑一次**。刚换过前缀 / 刚重签后常见，复跑就过；不是前缀没生效，别改脚本 |
| `认证已取消。Canceled by user.`（runner 已起，带 pid） | 手机上弹了**锁屏密码认证框**没人点。先确认 设置 → 开发者 → UI 自动化 打开，再让用户盯着手机在启动后输密码 |
| `Unable to find a destination matching` | 第一节第 2 条：设备断开或 UDID 不对 |
| `Timed out while enabling automation mode` | 原样复跑**一次**；第二次还是同一句就停，请用户去开 UI Automation 开关 |

**复跑上限：同一个签名出现两次就停**，去问用户或换排查方向。每次只改一个条件，看报错变不变。
