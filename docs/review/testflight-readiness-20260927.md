# TestFlight 送审就绪度 review（2026-09-27）

**范围**：工程离「拿到付费开发者账号 → 上传 → 外部测试」还差什么。基线 `origin/main` @ `b3b17ed`。
**外部规则**见 [`../research/testflight-readiness-delta-20260927.md`](../research/testflight-readiness-delta-20260927.md)
与 [`../research/beta-distribution-and-launch-gates-20260814.md`](../research/beta-distribution-and-launch-gates-20260814.md)；
**待办状态**以 [`../pre-launch-checklist.md`](../pre-launch-checklist.md) 为准（本文只记判断与证据，写完不改）。

## 0. 结论

**工程本身已经能打出合规的 Release 包，但还不能说「只差 Apple 账号」**：还有两项阻断是账号之前就能办、
而且不办就会发出坏包的。

| 类别 | 项 |
|---|---|
| 🔴 账号前必须办（不办 = 坏包 / 被拒） | ① 高德 iOS key 是占位值 ② 隐私政策与跑后记录的运动数据采集相矛盾 |
| 🔴 账号到手当天办（依赖账号） | ③ 加 Push Notifications capability ④ 生成 APNs `.p8` 交后端 ⑤ 建 App 记录 + Test Information + 演示账号 |
| ⚠️ 需要负责人拍板 | ⑥ Bundle ID 定不定 `com.jerry.aidrun` ⑦ 要不要支持 iPad ⑧ 个人还是组织账号 |
| ✅ 已就绪 | Release archive 可编、SDK 满足、build 号自增、出口合规、隐私清单、图标、账号删除、隐私政策 URL 上线、HTTPS、Release 锁云端 |

## 1. 实际跑过的验证

| 验证 | 结果 |
|---|---|
| `xcodebuild … -scheme blindRun-Prod -configuration Release … CODE_SIGNING_ALLOWED=NO archive` | `** ARCHIVE SUCCEEDED **`（两次：旧分支 `3f7785c` 与 main `b3b17ed`） |
| 产物 `Info.plist` | `com.jerry.aidrun` `1.0 (528)`，Widget 同为 `528`；`DTSDKName = iphoneos26.2`；`MinimumOSVersion = 16.0` |
| 产物 `AMapApiKey` | 🔴 **`CHANGE_ME_AMAP_KEY`** |
| 产物内 `*.xcprivacy` | 1 份（主 App 的，与 08-21 调研一致） |
| `scripts/testflight-upload.sh --dry-run` 验红 | 本机占位 key → `❌ 包里的高德 key 是占位值`，rc=1 |
| 同上验绿（临时假 key，跑完已恢复） | `✅ com.jerry.aidrun 1.0 (528)，高德 key 已配置`，rc=0 |
| `curl https://47.114.113.171/api/misc/legal-links` | 两个 URL 均非空（GitHub Pages），两页 200 |
| 服务器证书 | Let's Encrypt，notBefore 09-26 / notAfter 10-03 ⇒ 短期证书在自动续期 |
| **未跑** | 签名 archive、推送 entitlement 检查、上传 —— 都要付费账号 |

## 2. 阻断项

### ① 高德 key 是占位值 —— 真实影响是 TestFlight 包地图 / 定位 / 检索全部失效

- Key 由 `LocalConfig.xcconfig` 注入（`blindRun/Info.plist:5` 的 `$(AMAP_API_KEY)`），模板值见
  `LocalConfig.xcconfig.example:30`。**本机这份从来就是 `CHANGE_ME_AMAP_KEY`**，
  Debug 真机上地图一直走降级占位图，所以一直没暴露。
- 高德 iOS key **绑定 Bundle ID** ⇒ 与 ⑥ 相关：Bundle ID 改了就要重新申请。
- 机器守卫：`scripts/testflight-upload.sh` 在 archive 之后读产物 plist，占位值直接失败。
  （判在产物上而不是 xcconfig 上：继承链有 LocalConfig / Pods 两层，读源头会判错。）

### ② 隐私政策说「不收集运动数据」，App 在收

- 隐私政策 v1.1（2026-09-10）§2.6「我们**不**收集的」一栏写着「❌ 健康与运动数据」。
- 其后合入的 PR #189（`133b082`，09-24）在 `IN_PROGRESS` 期间经 WS `LOCATION_UPDATE` 上报
  `steps / cadence / alt`，`blindRun/Info.plist:22` 新增了 `NSMotionUsageDescription`。
- 后果：Guideline 5.1.1 / 2.3（元数据须如实）+ PIPL 告知义务；而且 App Store Connect 的 App Privacy
  问卷里要勾「健身」类数据，和政策原文对不上会被审核员直接拿来对照。
- 归属：`blindrun-legal` 仓库（GitHub Pages），不在本仓库。改法：把步数 / 步频 / 爬升移到「收集」一栏，
  写清用途（跑后记录）、采集时段（仅服务中）、可拒绝（不给权限照常陪跑）；版本记录照 v1.1 的格式补一条。

### ③④ 推送：工程没有 entitlements，后端缺 `.p8`

- `blindRun/Core/PushNotificationsManager.swift:61` 注册远程通知，而工程里**没有任何 `.entitlements` 文件**
  （免费个人团队签不了 Push capability，`:75` 的注释写明了这一点）⇒ 当前所有包都拿不到 token。
- 不是可以先提交的改动：现在加上 `aps-environment`，用免费团队 `ZW39BS8NXT` 的真机测试会签名失败。
  ⇒ 账号到手后在 Xcode 里点一次「+ Push Notifications」即可；上传脚本会检查签名产物，缺了就拦。
- 后端 `application.properties:124-128`：`apns.production=true`（与 TestFlight 的生产 token 匹配 ✅），
  `APNS_P8_PATH / KEY_ID / TEAM_ID / TOPIC` 全靠环境变量，当前为空。`APNS_TOPIC` = 最终 Bundle ID。
- 已知代价：生产网关收不了 Xcode 直装包的沙盒 token ⇒ 之后**真机调试收不到推送是预期行为**。
- `UIBackgroundModes` 里的 `remote-notification`（`blindRun/Info.plist:39`）**有用，别删**：
  后端 `PushyApnsServiceImpl.java:113-114` 发 `content-available=1`，用来在后台唤醒 App 补读通知（`9ea247d`）。

### ⑤ 审核员进得去、走得通

- 演示账号现成（`docs/test-accounts.md`：盲人、志愿者各有已认证的主号和备号，固定码 `000000`）。
- 但这几个号**同时在跑云端 E2E**。审核员一下单，就可能和自动化测试撞上 `DUPLICATE_ORDER`（时段冲突）
  或 `TOO_MANY_SCHEDULED_ORDERS`（最多 3 张）⇒ 建议后端开**审核专用的一对账号**。
- 审核员在美国：下单需要一位接单的陪跑员，而且起始时间要 ≥ 30 分钟以后。一个人拿一部手机
  走不完核心流程，是 2.1（App 完整性）被拒的高发场景 ⇒ 审核备注要写清两端怎么配合，**最好附一段录屏链接**。

## 3. 需要拍板

- **⑥ Bundle ID**：一旦在 App Store Connect 建了 App 记录就不能改。`com.jerry.aidrun` 里的 `jerry` 是原开发者；
  09-06 这个 ID 曾报「cannot be registered to your development team because it is not available」
  （记忆 `device-test-bundle-id-cannot-be-registered`），09-08 起又能用免费团队签了 ⇒
  它在付费团队下能不能注册，**只有拿到账号那一刻才知道**。改名涉及：pbxproj 5 个 target 的
  `PRODUCT_BUNDLE_IDENTIFIER`、高德 key、后端 `APNS_TOPIC`。
- **⑦ iPad**：`TARGETED_DEVICE_FAMILY = "1,2"`（`project.pbxproj:706` 等）⇒ 审核员可能在 iPad 上测；
  而 `pre-launch-checklist.md` §B2 把「iPad / 横屏体验」列在「不要拍」。只做 iPhone 可以减少审核面，
  但 AGENTS.md §3 要求发布验证跑 `iPad Pro (2)`，说明原本打算支持 iPad。
- **⑧ 账号类型**：见 checklist §H（组织账号要先办 D-U-N-S，周期以周计）。

## 4. 已就绪（逐项有证据）

| 项 | 证据 |
|---|---|
| Release 锁定云端、无环境切换器、无 UI 测试钩子 | `EnvironmentConfig.swift:10-33`（`.production → .demoCloud`，切换器只在 `.development`）；测试钩子在 `#if DEBUG \|\| DEMO`（`blindRunApp.swift:92`）⇒ **必须打 `blindRun-Prod`，别打 `blindRun-Demo`** |
| SDK 下限 | Xcode 26.2 / iphoneos26.2 ≥ 2026-04-28 起的 Xcode 26 要求 |
| build 号自增 | `scripts/set-build-number.sh:17` 取 `rev-list --count`；脚本要求 HEAD 在 `origin/main` 线上 |
| 出口合规 | `ITSAppUsesNonExemptEncryption = false`（`Info.plist:9`），只走系统 HTTPS，属豁免 |
| 隐私清单 | `blindRun/PrivacyInfo.xcprivacy` 四类 reason（08-21 调研结论） |
| 图标 | 3 张 1024（默认 / dark / tinted），`hasAlpha: no` |
| 权限文案 | 相机 / 定位（WhenInUse + Always）/ 麦克风 / 语音识别 / 运动，全部中文、写了用途 |
| 账号删除 | 两端都有入口（checklist §C2 已核） |
| 隐私政策 / 用户协议 URL | 线上 `legal-links` 返回非空，两页 200 |
| HTTPS | 09-08 起走 IP 证书，ATS 例外已删 |

## 5. 没覆盖

- 签名、推送、上传三步（要账号）
- 真机 UI 测试的已知红灯（记忆 `known-red-suites-hide-new-failures`：09-24 时 8 条与基线逐字相同）
  —— 不阻断上传，但送审包里是不是还藏着能被审核员碰到的缺陷，本轮没有按用例逐条判
- TestFlight App 自身的 VoiceOver 可用性（只能闭眼实测，checklist §D）

## 复核触发条件

- 拿到付费账号并完成首次上传（§2 ③④⑤ 与 §3 ⑥ 随之落定）
- 高德 key 配好 / 隐私政策改版
- 新增任何采集项或权限（重对 ②）
- 改 scheme / build configuration 结构（重对「必须打 Prod」）
