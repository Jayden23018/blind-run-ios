# AidRun 上线前检查单

**建立日期**：2026-08-14
**用途**：演示视频 → 盲人内测 → 中国区上架，三段路各自缺什么，做完一项打一个勾。
**状态图例**：`- [ ]` 待办 / `- [x]` 已完成 / 🔴 阻断（不做就发不出去）/ 🟡 应做 / ⚪ 可选

> **这份文档是活的**，不是快照。做完就地打勾并在行尾补一句「谁在什么时候验的」。
> 与 `docs/research/` `docs/review/` 的分工：那两处记事实与判断（带日期，写完不改）；
> 这里记**待办状态**（随时改）。
>
> 相关：拍摄规格见 [`research/demo-video-production-20260814.md`](./research/demo-video-production-20260814.md)；
> 分发规则见 [`research/beta-distribution-and-launch-gates-20260814.md`](./research/beta-distribution-and-launch-gates-20260814.md)；
> 功能缺口基线见 [`review/blind-app-full-review-20260812.md`](./review/blind-app-full-review-20260812.md)（⚠️ 已部分过期，见下 §B）。

---

## A. 演示视频（不被内测阻断项卡住，可以现在就开工）

### A1 开拍前置

- [ ] 🔴 **先拍 15 秒音频试片并回放确认有声音**。已有开发者实证 `AVAudioEngine` voice processing 活跃期间 iOS 内置录屏**整段没有音频**，而语音下单正落在这个面上。录一段「按住说话 → 识别 → 播报确认」，导出到 Photos 回放。**不要等剪辑时才发现素材是哑的。**
- [ ] 🔴 两台真机就位并都能装上当前构建（模拟器通道永久不可用 —— 高德无 arm64-sim slice）。盲人端一台、志愿者端一台，全流程需要两端配合。
- [ ] 🔴 两个演示账号可用：一个 BLIND、一个 VOLUNTEER，均已完成实名/资质，志愿者已通过管理员审核并打开「接单开关」（默认 `isAvailable = false`）。预置账号验证码固定 `000000`（`docs/test-accounts.md`）。
- [ ] 🔴 志愿者账号确认能收到 `NEW_ORDER` 派单推送 —— 后端只向满足派单条件的在线志愿者推，收不到就录不成接单镜头。
- [ ] 🟡 高德 key 已配到 `LocalConfig.xcconfig`。**没有 key 时地图一律降级成占位图**，录出来是灰底方块。
- [ ] 🟡 录屏前设备状态：静音勿扰开、通知清空、电量满、状态栏干净、屏幕亮度拉高。
- [ ] ⚪ 备选录制通道试一次：USB 连 Mac → QuickTime → 新建影片录制，**Camera 和 Microphone 都要选 iPhone**（只选 Camera 会录成 Mac 的麦克风），编码选 SDR。

### A2 拍摄

- [ ] 🔴 **出镜同意走口头宣读 + 录像记录**，不要求盲人在看不见的纸上签字。讲清用途（宣传/官网/教学）、留存期限、撤回渠道。
- [ ] 🔴 实拍外接麦克风（风声是这类片子毁片率最高的原因）。
- [ ] 🟡 同一流程录 3 遍以上，留剪辑余地。
- [ ] 🟡 多拍空镜：脚步、手握牵引绳特写、路面、清晨光线。剪辑时救命的都是这些。
- [ ] 🟡 盲人用户本人的一句原声（比任何旁白都强）。

### A3 剪辑与导出（**两个版本，不能共用一个导出文件**）

- [ ] 🔴 母版 60–90 秒：官网 / 内测分发 / 微信传播用。结构 Hook → Problem → Solution → Proof → CTA，**前 10–15 秒定生死，不要放 logo 动画开场**。旁白 150–180 字。
- [ ] 🔴 **硬字幕烧进画面**（WCAG 1.2.2 A 级；且平台会丢字幕轨）。人工校对，自动生成的不够用。
- [ ] 🟡 官网页面上放一份完整文字稿（等于文字替代 + 可被搜索引擎索引）。
- [ ] 🟡 旁白里把关键视觉信息说出来（等于内嵌音频描述，WCAG 1.2.5 AA）。
- [ ] 🔴 官网 hero 版：**整个删掉音轨**（`-an`，空音轨会挡自动播放）、≤4MB 桌面 / ≤2MB 移动、`autoplay muted loop playsinline`、`-movflags +faststart`、poster 图才是 LCP 元素。
- [ ] 🟡 App Store 版（约 27 秒，从母版重剪）：**删掉全部真人镜头**（Apple 逐字禁止拍摄人操作设备）、886×1920、30fps、H.264 High L4.0、**AAC 立体声 256kbps**（与 hero 版相反，这版必须有音轨）、默认静音播放所以字幕要大。

### A4 交付前逐条自查（**守卫拦代码，拦不到视频，只能靠人**）

- [ ] 🔴 全片没有「已通知家属」「联系人已收到短信」「已送达」这类说法。旁白、字幕、演示画面一律。
- [ ] 🔴 演示首页求助条时说清：非服务中状态它是**本地拨号**，App 不会代你发送求助。
- [ ] 🔴 没有真实手机号、真实住址、真实身份证号、真实定位坐标出现在画面里。
- [ ] 🔴 字幕里的状态词与 App 内一致。禁用词：`已提交` `已联系` `匹配中` `已接受` `已到达`。
- [ ] 🔴 只演示当期真有的功能（见 §B）。**demo 跑在产品前面**对承诺人身安全的产品是致命的。
- [ ] 🔴 脚本里没有「现在就跑」—— 下单起始时间距今必须 ≥30 分钟。
- [ ] 🔴 自检一次：把「盲人」这个设定拿掉，这还是个故事吗？不是的话重写（避开 inspiration porn）。
- [ ] 🔴 成片在公开前给出镜的盲人用户本人过目确认。

---

## B. App 现状：哪些能拍，哪些不能

**基线**：`origin/main` @ `ff8159b`（2026-08-14）。
⚠️ `review/blind-app-full-review-20260812.md` 那句「必须项 20 条只达成 9 条」**已经过期** ——
之后合入的 PR #20–#24 与多个 OpenSpec 变更补上了一大批。下表是本轮重新核过的。

### B1 可以放心拍（有 UI 入口、走真实端点）

| 能力 | 证据 |
|---|---|
| 手机号 + 验证码登录、角色选择 | 后端 `sms.provider=aliyun`（真实短信），预置账号固定码 `000000` |
| 盲人实名认证（下单硬门槛）| `BlindIdentityVerificationView.swift` |
| 语音下单全流程（说需求 → 确认 → 下单）| 全 App 最扎实的一块 |
| 首次使用引导 | `blindRunTests/BlindFirstRunHelpTests.swift` |
| 常用地址 / 收藏地点 | `blindRunTests/FavoritePlaceStoreTests.swift` |
| 派单 → 接单 → 在路上 → 已到达 → 服务中 → 完成 | 完整状态机 |
| 「继续等待」避免自动取消 | `blindRunTests/KeepWaitingTests.swift` |
| 志愿者位置实时可见 | `GET /api/blind/volunteer-location` + WS |
| 求助 SOS（仅服务中）+ 二次确认 | `EmergencySOSTests` 逐状态钉住 |
| 紧急联系人管理（1–5 人）| `EmergencyContactsView.swift` |
| 行程分享给紧急联系人 | `RunPlanLiveShareTests` / `RunPlanShareConsentTests` |
| 约定结束时间 + 超时告警 | `PlannedEndAndOverdueTests` |
| 跑后轨迹总结与历史记录 | `CompletedTrackSummaryView` / `BlindRunHistoryView`（PR #24 已合）|
| 志愿者服务认可体系 | `VolunteerAchievements.swift` |
| 评价读取与状态流水 | `OrderReviewAndStatusLogDecodingTests` |

### B2 不要拍

| 项 | 原因 |
|---|---|
| 隐私号中转拨号 | 后端 `aliyun.private-number.enabled=false`，端点返回 `NOT_AVAILABLE` 且响应体无号码。**现在拨号是直拨真实手机号** |
| iPad / 横屏体验 | `horizontalSizeClass` 全仓 **0** 命中（仅 `verticalSizeClass` 5 处）。iPad 上会难看 |
| 平台内文字消息 | 不存在，跑前沟通只能打电话 |
| 固定搭档 / 收藏志愿者 | 不存在，每单重新派 |
| 用户侧客服/申诉入口 | 后端 `/api/cs/*` 全是坐席侧，C 端提交端点不存在 |
| ~~账号注销~~ | ~~iOS 端**没有入口**~~ → **可以拍**，两端都有入口且走真实端点（2026-08-15 订正，见 §C2）|

### B3 拍之前先在真机上走一遍确认

- [ ] 🔴 **状态流转能不能连续拍完**。30 分钟提前量只卡在下单（`VoiceOrderService.java:601/856`），状态流转端点上**没找到时间守卫** ⇒ 理论上可以「下单（T+31min）→ 志愿者秒接 → 立刻 en-route / arrived / start-service / finish」一气呵成。**这条是 grep 结论，必须真机验一遍**，它决定整个拍摄日程能不能压进一个上午。
- [ ] 🟡 语音识别在拍摄现场的实际成功率（户外噪音下）。
- [ ] 🟡 VoiceOver 开着时同一句会不会「念两遍」（通告 + 合成器两条通道，`tts-rate-follows-voiceover-20260814.md` 标为未解决）。

---

## C. 内测发出去之前（🔴 全是阻断项）

> 关键认知：**外部 TestFlight 的首个构建就要过 App Review**，
> 所以 5.1.1 那一整组不是「上架前再补」，是**内测第一天就生效**。

### C1 账号与通道

- [ ] 🔴 **【第 0 项，今天就办】购买 Apple Developer Program 账号**（$99/年）。2026-08-14 确认：**目前没有付费账号**，而内测是异地分发（团队与测试者不在同一城市，线下陪同不可行）⇒ TestFlight 是唯一现实通道 ⇒ **没有付费账号，整个 §C 和 §D 一步都走不了**。
  - 个人账号（Individual）：审核通常 1–2 天，App Store 上显示**个人姓名**
  - 组织账号（Organization）：显示公司名，但要先办 **D-U-N-S 编号**，周期**以周计**
  - ⇒ 选哪种要先定（见 §H），因为组织账号的等待期决定整个内测时间表
- [ ] 🟡 工程文件里写死的 `DEVELOPMENT_TEAM = R6PH2TFB3Q` 是原开发者的团队号，本机签名用 `ZW39BS8NXT`。新账号开好后确认 App Store Connect 记录归属，命令行传 `DEVELOPMENT_TEAM=<新团队号>` 覆盖（**不要改 pbxproj，那是行级冻结项**）。
- [ ] 🔴 Bundle ID `com.jerry.aidrun` 在目标团队下已注册，且 App Store Connect 里有对应 App 记录。
- [ ] 🔴 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 从 `1.0` / `1` 起版本策略定好（每次上传 build 号必须递增）。
- [ ] 🟡 Info.plist 补 `ITSAppUsesNonExemptEncryption`，否则每个构建上传后都要手工回答出口合规问题。
- [ ] 🔴 填好 Beta App Description 与 **Beta App Review Information**，附**演示账号**（预置手机号 + 验证码 `000000`），否则审核员登不进去必被拒。
- [x] ~~决定内部还是外部~~ → **走外部测试**（2026-08-14 定）。内部测试要求每位测试者持有 App Store Connect 用户身份，对异地的盲人测试者不现实 ⇒ 接受 Beta App Review 这道等待。
- [ ] 🟡 记住构建 **90 天过期**，内测周期超过 90 天要重新上传。

### C2 法律与合规

- [ ] 🔴 **隐私政策与用户协议正文写出来并挂到可访问 URL**。已实测 `GET /api/misc/legal-links` 线上返回 `{"privacyPolicyUrl": null, "userAgreementUrl": null}` —— iOS 侧入口（`LegalDocumentsView.swift`）**已经做好了，就等 URL**。这是 App Review 5.1.1 的硬阻塞，也是收集真实用户身份证号/轨迹的法律前提。**归后端/运营。**
- [x] ~~🔴 **iOS 端做账号注销入口**~~ → **本来就有，这条断言是错的**（2026-08-15 核实并订正）。
  盲人端 [`BlindRunnerSettingsView.swift:67`](../blindRun/BlindRunner/BlindRunnerSettingsView.swift)「删除账户」、
  志愿者端 [`VolunteerOrderFlowViews.swift:2071`](../blindRun/Volunteer/VolunteerOrderFlowViews.swift)，
  两道确认 + `AccountDeletionViewModel` 先 preflight 查活跃订单（被拦时**语音播报**原因），
  真实调用在 [`AppState.swift:534`](../blindRun/Core/AppState.swift)
  `apiClient.delete("/api/users/\(userId)")`，失败重试在 `ContentView.swift:489`，
  单测 `blindRunTests.swift:2349` + UI 测试 `blindRunUITests.swift:880-893` 都在。
  - ⚠️ **写错的原因值得记一笔**：搜的是「注销 / deleteAccount / 删除账号」，
    代码里写的是「**删除账户** / `deleteCurrentAccount`」—— 同义词错开，两个人先后判成「零调用点」。
    断言某功能「不存在」之前，至少换一组近义词再搜一遍。
  - 后端实际行为（`origin/main` 的 `UserService.deleteAccount`，2026-08-15 读）：用户行软删除、
    手机号改写成 `deleted_{id}_{phone}` 释放可重注册、`name` 置空；**PII 级联硬删**（盲人：实名资料 /
    紧急联系人 / 常用地址；志愿者：证件照 OSS / 资料 / 可服务时间；两端：轨迹点 / 工单 / APNs token）；
    **订单、评价、求助事件刻意保留**（不存 PII，留作纠纷复核审计）。现有确认文案与这些逐条对得上。
  - 剩下的唯一小缺口：确认弹窗没逐项说清**删什么、留什么**（PIPL 第 47 条下用户有知情权）。已单独处理。
- [ ] 🔴 身份证号与行踪轨迹的**单独同意**（PIPL 第 29 条）在收集点逐一核对。行程分享那条已经做了（`RunPlanShareConsent.swift`），**实名认证那屏要确认也有**。
- [ ] 🟡 紧急联系人是第三方，其手机号未经本人同意即被收集。确认后端 `contact-added` 短信模板（`SMS_505950033`）真的在发告知短信。
- [ ] 🟡 隐私政策里逐条列全实际收集项：手机号、身份证号姓名、实时位置与轨迹、麦克风与语音内容、紧急联系人手机号、相机（志愿者活体认证）。
- [ ] 🟡 App Store Connect 的 App Privacy（隐私营养标签）按上一条如实填写。

### C3 安全

- [ ] 🔴 **后端做一次收窄范围的安全 review**。2026-08-14 核实：后端仓库**没有 `docs/review/`，没有任何成体系的 review 或安全审计文档**。现有的质量手段是 `docs/ISSUES.md`（248K，缺陷按 N 编号逐个追踪，已到 N67）+ 单点的 per-PR code review。四条理由说明这不够：
  1. 后端是当前**三条内测阻断项里两条的归属方**（隐私政策 URL、HTTPS）
  2. 它处理身份证号、JWT、实时位置、双方手机号、活体认证 —— **`~/.claude/rules/common/core.md` 里「必须叫 security-reviewer」的触发条件基本占全了**
  3. 当前是**明文 HTTP**，任何认证/授权缺陷的利用门槛都被拉到最低
  4. 「按 N 编号逐个修到 N67」说明缺陷是**被撞见**的，不是**被扫出来**的 —— 没做过系统性排查
  - **范围要收窄，不要「全量 review」**，按风险面切三块：① 认证与授权（JWT 生命周期、角色越权、客服/管理端边界）② 敏感数据的存储与传输（身份证号、轨迹、手机号、日志脱敏）③ 位置与 SOS 链路（坐标真实性、求助事件不可篡改、短信通道）
  - 产出落在**后端仓库**的 `docs/review/`（那边还没有这个目录，等于顺手把 §13 那套约定也建起来）


- [ ] 🔴 **后端上 HTTPS**。当前 `http://47.114.113.171` 是明文，Info.plist 挂着 ATS 例外（`NSExceptionAllowsInsecureHTTPLoads`）。走明文的是 JWT、身份证号、实时坐标、双方手机号 —— **给真实盲人用户使用前必须换掉**。这不是审核问题，是事故风险。**归后端。**
- [ ] 🟡 HTTPS 就位后删掉 Info.plist 里的 `NSAppTransportSecurity` 例外块。
- [ ] 🟡 确认阿里云短信账户余额与日发送配额够内测规模（当前限流：单号 60 秒 1 条、每日 5 条）。

---

## D. 盲人内测专属

- [ ] 🔴 **自己闭眼实测一遍分发链路**：干净设备开 VoiceOver，全程不看屏幕走「收到邀请邮件 → 装 TestFlight → 兑换 → 装 App → 首次启动 → 登录」。**这一段不在我们代码里，改不了**，卡住只能靠陪同安装或电话协助。没实测过就发出去，等于把最难的一步丢给用户。
- [ ] 🔴 写一份**纯文字版安装说明**（不要图片步骤图，不要 PDF 扫描件），发到测试者手机上可被读屏朗读。
- [ ] 🔴 反馈通道对盲人可用：**电话 / 微信语音**优先，不要只给在线表单。
- [ ] 🔴 内测知情同意：说清收集哪些数据、存多久、怎么删、出事找谁。口头宣读 + 录音留证。
- [ ] 🔴 **异地内测，没有现场陪同**（2026-08-14 确认：团队与测试者不在同一城市）。这把两件事顶成硬需求：
  - **远程协助通道必须真的能用** —— 首次安装与首次下单要能靠一通电话走完，实测一遍全程口述能不能带对方装上
  - **本地陪跑伙伴由谁保障** —— 户外陪跑本身有人身风险，异地团队出不了现场。测试者所在城市有没有志愿者供给，是内测能不能真跑起来的前提，不是技术问题
- [ ] 🟡 内测期间的真实 SOS 演练怎么处理，事先和测试者讲清楚（**不要**让他们真按求助键测试云端链路）。
- [ ] 🟡 测试者招募渠道：残联 / 盲人按摩院 / 视障跑团。人数建议首轮 3–5 人，不要一次铺开。
- [ ] ⚪ 准备一份「已知问题清单」随包发出（B2 那张表就是初稿），避免重复反馈。

---

## E. 内测期间

- [ ] 🟡 崩溃与异常有回收通道（Xcode Organizer / TestFlight 崩溃报告至少看一个）。
- [ ] 🟡 每次真机验证按 `scripts/device-test.sh` 走，**`passed=0` 一律当失败查**。
- [ ] 🟡 每轮反馈按「现象 → 根因 → 规则」归档，犯过第二次的落成 hook 或测试（`AGENTS.md` §1）。
- [ ] ⚪ 内测满 90 天前重新上传构建。

---

## F. 中国区上架（周期以周计，现在就并行启动）

> **TestFlight 不是上架的前置。** 构建传到 App Store Connect 后就在可发布池里，
> 直接提交 App Review 即可，两条路并列不是先后。而且 TestFlight 外部测试的 Beta App Review
> 与 App Store 的 App Review **是独立的两道** —— 先走外部内测再上架 = **过两次审**。
> 我们仍然选择先内测，因为盲人用户的真实反馈值这道额外等待；但要知道代价是多一个审核周期。


> 这条链**不卡内测**，但每一步都有外部等待时间，不提前启动就是上架时它卡着。

- [ ] 🔴 买域名。
- [ ] 🔴 域名 ICP 备案（服务器在阿里云大陆节点，走阿里云接入商）。**裸 IP 无法备案。**
- [ ] 🔴 公安备案（ICP 备案成功后 30 天内）。
- [ ] 🔴 配 HTTPS 证书，App 改走 `https://域名`（与 §C3 是同一件事）。
- [ ] 🔴 App 备案，拿到备案号填进 App Store Connect。2024-04-01 起无备案号无法发布更新且会被强制下架。
- [ ] 🟡 App Store 截图、描述、关键词、分级。
- [ ] 🟡 App Preview 视频（§A3 那版）上传，每个语言最多 3 条。
- [ ] ⚪ 向 Apple Developer Support 书面确认「TestFlight 是否校验备案号」—— 本轮**没拿到一手依据**，两个对口的官方页都 404。

---

## G. 每次构建前的例行门禁（已有脚本，装一次钩子即可自动）

```bash
scripts/install-git-hooks.sh
```

- [x] 契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料 / 确认轮词表 —— pre-push 自动跑（5 条）
- [ ] 🟡 `openspec validate --all --strict --no-interactive`
- [ ] 🟡 `node scripts/validate-docs.mjs`
- [ ] 🟡 12 个未归档 OpenSpec 变更逐个判：`capture-and-gate-runner-extra-needs`（22 未完成，进度最落后）与 `enable-one-utterance-booking` 都在动语音下单对话流，**可能 delta 同一个能力**，开工前先判会不会打架。

---

## H. 待确认（需要人回答，不要自己猜）

- [ ] **Apple Developer Program 账号在谁名下？** 是个人账号还是组织账号（组织账号需要 D-U-N-S，办理要时间）。App Store Connect 的 App 记录归 `R6PH2TFB3Q` 还是 `ZW39BS8NXT`？
- [ ] **视频的最终投放位置**是哪几个？官网首页 / 微信 / App Store 三选几？决定要导出几个版本。
- [x] ~~内测是 TestFlight 还是线下陪同？~~ → **TestFlight 外部测试**（2026-08-14 定，异地，线下陪同不可行）。
- [ ] **付费开发者账号选个人还是组织？** 组织账号要先办 D-U-N-S，周期以周计，会直接决定内测时间表。另注：本产品收集身份证号与实时轨迹并承诺人身安全，用**个人**账号上架、产品页显示个人姓名是否合适，值得和导师确认一次。
- [ ] **隐私政策和用户协议谁来写？** 这是 §C2 的第一阻塞项，且不是代码工作。
- [ ] **后端上 HTTPS 有没有排期？** 决定内测能不能用真实用户数据。
- [ ] **有没有伦理审查要求？** 学校/导师侧若需要走 IRB 类流程，是另一条路径。
