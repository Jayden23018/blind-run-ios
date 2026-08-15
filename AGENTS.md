# AGENTS.md

AidRun / 助盲跑 的最高优先级工作契约。**不是产品头脑风暴，是硬约束。**

**仓库边界**：这是 AidRun 原生 iOS 前端仓库。它不包含、不维护、不构建、不部署后端代码。后端是外部服务，当前真实集成端点是 `http://47.114.113.171`。除非项目负责人在单独的变更里显式改变边界，否则不得加入服务端源码、数据库配置、服务端构建脚本或可本地运行的后端。

## 0. 按需加载的规则（不在本文件，用到再读）

| Skill | 什么时候读 |
|---|---|
| `aidrun-auth` | 登录、验证码、JWT、角色、下单前置条件 |
| `aidrun-a11y-voice` | 盲人端 UI、VoiceOver、语音输入/播报、高德地图、定位与坐标系 |
| `aidrun-error-codes` | 处理 API 错误、写 TTS 错误播报、新增错误分支 |
| `aidrun-ship-check` | 实现完成、准备提交、准备宣称「做完了 / 测试通过」 |

## 1. 事故复盘规则（最重要的一条）

任何一个**已经犯过第二次**的错误，**或单次就耗掉三次以上尝试才对**的东西，必须落到下面四者之一，**不许只写进文档**：

1. 能被静态检查抓到 → `scripts/hooks/guard.mjs` 加一条守卫
2. 能被运行时检查抓到 → 加一条测试（优先 `blindRunTests/Fixtures/` 的真实响应回归）
3. 能被「该做没做」抓到 → 加进 Stop 钩子 `scripts/hooks/stop-checklist.mjs`
4. 三者都不能（纯语义认知）→ 写进项目记忆，并在本文件留一行索引

只写文档不算完成。文档挡不住重复犯错，这条规则的存在就是因为它已经被证明挡不住。

**「卡了很久」不必等到第二次。** 触发条件原本只有「犯过第二次」，于是第一次就试了六遍才对的东西
没人管 —— 代价已经付了，不落地下个会话从头再踩。Stop 钩子每会话问一次这件事
（`stop-checklist.mjs`，只在已有欠账时附带，不做独立触发条件）。

**「反复查」和「反复错」同等对待。** 同一个事实如果第二次还要重新 grep / 重读文件才能确定
（某个函数在哪、某个脚本叫什么、某个字段的真实类型），那不是记性问题，是事实没落地：
就地把它写进本文件或对应 skill，带上 `文件路径:行号`。上面 §1.1 那条 `guard.sh` → `guard.mjs`
就是例子 —— 文件早改名了，规则里没跟，于是每次都要重查一遍才发现引用是错的。

**已归档的语义认知（§1.4）索引：**

- 单测里构造硬件服务当「缺失状态」的前提是竞态：真机 CoreLocation 几毫秒就回调，
  用 `LocationService.simulateMissingDeviceLocationForTesting()`（`blindRun/Map/LocationService.swift:169`）钉死。
  详见记忆 `location-service-test-seam-and-weak-viewmodel-deps`。
  另一半陷阱（view model 依赖是 `weak`，传临时对象等于传 nil）已按 §1.1 落成守卫规则
  `weak-temporary`，不再靠人记。

- 本仓库有**两条**无障碍通道，只有 VoiceOver 那条被验收过。低视力用户的视觉通道
  （对比度 / 横屏与 iPad / Dynamic Type 上限）从没被系统性检查过，三块空白打的是同一群人 ——
  而 `VisionLevel.LOW_VISION` 在数据模型里是一等公民。改盲人端 UI 时要**问两遍**：
  VoiceOver 用户怎么样？不开读屏、字调到 AX5、横屏、户外的低视力用户怎么样？
  详见记忆 `low-vision-visual-channel-unaudited` 与 `docs/review/frontend-backend-alignment-review-20260812.md` §D。
  这条抓不成静态守卫：对比度要看颜色**用在什么语义的文本上**（装饰图标不算），机器分不出来。

- XCUITest 报 `Failed to get matching snapshots: Timed out while evaluating UI query` 时，
  **先看 result bundle 里的屏幕录像找误触，不要去 grep 重绘循环**。2026-08-14 那次的真因是
  「重复当前状态」在首屏外、不滚就 `tap()`，触点被钳到底部常驻求助条上，一路误触到
  `tel://110`，超时的是对系统 `com.apple.BusinessActionSheet` 的查询。
  连带一条反直觉的事实：SwiftUI `ScrollView` 屏幕外的子视图**照样** `isHittable == true`
  （`List` 是压根不渲染，两种坑不一样），所以 `scrollUntilExists` 对它无效，要用
  `scrollElementIntoView`（`blindRunUITests/blindRunUITests.swift:1225`）。
  误触本身已按 §1.2 钉成运行时断言；「怎么诊断」这半条抓不成检查，
  详见记忆 `snapshot-timeout-means-a-system-app-took-over`。

## 2. 源真相优先级

冲突时按此顺序：

1. `AGENTS.md`
2. `plan.md`
3. `docs/01-product-requirements.md` → `02-mvp-scope` → `03-user-stories` → `04-user-flows-and-state-machine` → `05-page-specs` → `06-data-model` → `08-ios-architecture` → `09-accessibility-and-voice-guidelines` → `10-ai-coding-tasks`
4. `openspec/changes/` 下的 OpenSpec 变更
5. 遗留 Flutter 代码只能当 UI / 行为参考，**不是**源真相

`docs/_archive-*.bak` 是已知有错的旧契约副本，**不得读取或复制**。

## 3. 生产方向

- 本仓库只有 iOS 原生 App；后端是仓库外的云服务。
- Swift + SwiftUI 优先，必要时才桥接 UIKit；iOS 16+；MVVM。
- 所有真实 HTTP 走 `http://47.114.113.171`，所有真实 WebSocket 走 `ws://47.114.113.171`。**地址在 App 内不可配置，不得加入本地或占位的真实服务端地址。**
- REST + WebSocket 提供通知、派单、状态更新与位置上报；JWT Bearer Auth。
- 用高德地图与真机定位；TTS 用 `AVSpeechSynthesizer`，STT 用 iOS `Speech`。
- Mock 是**进程内**的前端测试设施，不发网络请求，且**永远不足以作为发布签核依据**。
- 发布验证必须在真机 `111` 与 `iPad Pro (2)` 上跑。

生产短信、实名认证、管理员工具、路线导航、支付等能力不再被全局禁止，但仍必须先有需求、API 契约、实现计划与验收测试才能写代码。

## 4. 范围规则

一次只实现一个内聚模块；不得静默扩大范围；不得一次重写整个项目。新的生产能力必须记录文档、API 契约影响、测试计划与发布风险。若某能力需要后端改动，写下 `需要人工确认` 并把缺失的 API/行为说清楚，iOS 侧实现留在明确的契约后面。

## 5. 订单状态机

**只允许**这些状态：

```
PENDING_MATCH  PENDING_ACCEPT  IN_PROGRESS  DRIVER_EN_ROUTE  DRIVER_ARRIVED
COMPLETED  CANCELLED  REMATCHING  NO_VOLUNTEER
```

**禁用的遗留词汇**（`scripts/hooks/guard.mjs` 会拦）：

`submitted` · `contacted` · `expired` · `matching`（用 `PENDING_MATCH`） · `accepted`（用 `PENDING_ACCEPT`） · `arrived`（用 `DRIVER_ARRIVED`） · `emergency`（求助是独立事件，不是订单状态）

正常流转：

```
PENDING_MATCH → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED
```

取消流转：

```
PENDING_MATCH / PENDING_ACCEPT → CANCELLED（盲人 token）
PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS → REMATCHING（志愿者 token）
REMATCHING → CANCELLED（只能盲人 token）
```

- 取消端点 `POST /api/orders/{orderId}/cancel`，无需请求体。
- 盲人只能取消 `PENDING_MATCH` / `PENDING_ACCEPT` / `REMATCHING`；`IN_PROGRESS` 期间**不得**展示取消入口。
- 志愿者只能取消 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`。
- `REMATCHING` 是已接单志愿者取消后进入的状态，此后只能盲人用自己的 token 取消 —— 那个志愿者已不是订单参与者。
- 状态流转端点统一 `POST /api/orders/{orderId}/{action}`：`respond`（体带 `action = ACCEPT|DECLINE`）、`en-route`、`arrived`、`start-service`、`finish`。
- 下单起始时间距今不足 30 分钟必须返回 `APPOINTMENT_TOO_SOON`（`EnvironmentConfig.minimumBookingLeadMinutes = 30`）。**没有「现在就跑」。**
- 订单列表用分页响应 `PagedOrderResponse`；盲人订单详情每 5 秒轮询作为 WebSocket 兜底。
- WebSocket 端点：`/ws/blind?token={jwt}` 与 `/ws/volunteer?token={jwt}`。

## 6. 求助 / SOS 红线

- 求助**不是**订单状态。`POST /api/emergency/trigger` 只记录事件，订单状态不变。
- **两端入口都只在 `IN_PROGRESS` 开放**（`EmergencyTriggerRequest` 必须带 `orderId`）。
- 盲人首页那条常驻求助条是**唯一的例外形态，且它不是例外**：`IN_PROGRESS` 时走上面这条云端链路，
  其余任何状态一律降级为**本地拨号**（主紧急联系人 / 110），**绝不调 `POST /api/emergency/trigger`**。
  降级分支的文案必须说清「App 不会代你发送求助」—— 按下去只有拨号音，不说清等同于让盲人以为求助已发出。
  判定在 `BlindHomeSOSMode.resolve`（`blindRun/Safety/SafetyModule.swift`），
  用例 `EmergencySOSTests.testHomeSOSBarOnlyUsesTheCloudPathDuringInProgress` 逐状态钉住。
- 志愿者端入口自 2026-07-31 起**已开放**。此前长期关闭的理由是「后端把事件挂在触发者身上，志愿者按下只会惊动自己、升级到自己的联系人」；后端 commit `a5ba523`（SOS-1）已把 `event.userId` 改为取订单的盲人方，用 `TriggerType.VOLUNTEER_BUTTON` 区分来源，该理由不再成立。
- **志愿者不得拥有「误触」按钮**：一对一陪跑里志愿者可能就是威胁来源，后端一律回 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`。撤销权只在受助者本人（`PUT /api/emergency/{id}/cancel`）和客服手里。
- **App 永远不得宣称短信已发出、已送达，或家属/联系人已被通知。** `EMERGENCY_CONTACT_NOTIFIED` 是在触发事务内同步推送的（`EmergencyService.java:370-373`），而短信是事务提交后异步发的（`EmergencyContactNotifier.java:60-62`）；短信失败只播给客服（`:126-135`），**从不回告盲人**。iOS 必须用自己的进行时文案覆盖后端的完成时态 body。字符串 `联系人已收到短信` 不得出现在发布产物中。
- 云端 SOS 请求必须带**新鲜的真实 GCJ-02 坐标**。拿不到就不发，并且**可见且可听**地告知用户。Mock / demo 坐标绝不上传。后端技术上接受的无 GPS 降级提交被 `EmergencyCoordinator.allowsSubmissionWithoutLocation` 关着，在产品/安全批准前保持 `false`。
- 后端的 `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST` 只是高优先级的**信息性**安全提示，不改订单状态、不启用求助 UI、不证明救援已派出。
- 求助必须二次确认，文案**逐字锁定**：

```text
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

## 7. 外部 API 契约

- **契约唯一源在后端仓库** `/Users/mac/Downloads/demo`：REST 看 `docs/api_spec.yaml`，WebSocket 看 `docs/websocket-protocol.md`。本仓库**不留副本**。
- 契约工作用 `claude --add-dir /Users/mac/Downloads/demo` 挂载。契约文档本身错了就去后端仓库改，不要在这里存第二份。
- 需要后端拍板的问题写进 `demo/docs/handoff.md` 的「待后端确认」。
- 错误码语义见 skill `aidrun-error-codes`；机器可读版本是 `docs/error-codes.json`。

## 8. iOS 硬规则

- 原生 Swift + SwiftUI + MVVM，iOS 16+，网络用 `URLSession`。
- 网络请求集中在 `APIClient`；token / `currentUser` / `activeRole` 集中在 `AppState`。
- Token 存 Keychain（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`）。**不要把 access token 写进 `UserDefaults`。**
- View 只负责渲染与交互；ViewModel 持有状态并发起 API 调用。
- 开发期支持 Mock / Demo Cloud 切换；Demo 与 Production 构建锁定 Demo Cloud。
- **高德 key 只能来自本地配置文件，不得硬编码，不得提交真实 key**，并提供示例配置文件。
- 志愿者默认 `isAvailable = false`，必须手动打开才开始接单；关闭不影响当前订单。
- 接单前隐藏盲人联系方式、紧急联系人与敏感健康信息；接单后展示完整手机号。
  **判据是字段的取值空间封不封闭，不是字段名听起来敏不敏感** —— 枚举 / 布尔（导盲犬、配速、
  引导方式）可以逐个判定「这个值给陌生人看行不行」，所以能留在接单前；**自由文本一律接单后**，
  因为同一个输入框里写「沿湖边跑道」和「我住院刚出来只能走平路」都自然，展示前分不出是哪一种。
  用途会漂移，类型不会。新增字段照这条判，不必每次重新讨论。
  实现闸：`RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`（穷举 switch，后端加状态时编译器会逼一次决策）。

## 9. 冻结文件

**整文件冻结**：`Podfile` —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。

**行级冻结**：`blindRun.xcodeproj/project.pbxproj` —— 文件可以改（例如加 SPM 依赖），但改动内容**不得触及 `DEVELOPMENT_TEAM`**。写死的 `R6PH2TFB3Q` 是原开发者的团队号，命令行传 `DEVELOPMENT_TEAM=ZW39BS8NXT` 覆盖。

**任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无 arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，行尾加 `guard:allow excluded-archs`。

> 2026-08-06 从整文件冻结改为行级。核对后发现原先给的两条理由只有一条落在 pbxproj 上（`DEVELOPMENT_TEAM`，12 处）；`EXCLUDED_ARCHS` 在 pbxproj 里出现 **0 次**，它只存在于 `Podfile:36`。整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」依赖人记得加回来 —— 第 1 节说的就是这种挡不住重复犯错的做法。
>
> 守卫在 `scripts/hooks/guard.mjs`，自测在 `scripts/validate-guard.mjs`（CI 与 pre-push 都跑）。
> 守卫管的不止冻结文件，还有遗留状态词、SOS 文案、服务端地址、高德 key、OpenAPI 运行时越界、
> weak 依赖收临时对象、workflow 的 `if:` 里用 `secrets`。规则清单以 `guard.mjs` 为准，本文件不留副本。

## 10. 工作流

**开工前**

1. 先读 `AGENTS.md`
2. 再读相关 docs 与 OpenSpec
3. 判一次这活要不要派 subagent —— 判定表在全局 `~/.claude/CLAUDE.md` 的「委派」节，**本文件不留副本**（理由同 §7：两份会漂移）。一句话版：定位/摘要/读日志外包，设计与编辑自己干

> 开场不用手查的那几条事实由 SessionStart 钩子 `scripts/hooks/session-context.mjs` 自动注入：
> 分支与脏文件数、未归档 OpenSpec 变更、后端契约可读性，以及**本机护栏三项**
> （pre-push 钩子装没装 / 有没有 `fork` remote / 双推配没配）。
> 三项全绿时不输出 —— 每轮都响的提醒会被无视，报缺口才有信息量。
> 自测 `scripts/validate-session-context.mjs`（6 条，CI 与 pre-push 都跑）：
> 配齐的机器永远走不到告警分支，坏了只会安静地不再提醒。

**实现中**

4. 一次只实现一个内聚模块
5. 行为有变时，实现前先确认对应 spec
6. **改任何文件前，自己完整读一遍那个文件** —— 探索可以外包，编辑不行

**收尾：三件事，缺一件都不算做完**

7. 跑测试、更新必要文档，按 skill `aidrun-ship-check` 的格式输出
8. **同步 handoff**（`demo/docs/handoff.md`）：
   - 全文近 3000 行，**只读末尾最新几条**（`tail -80`）或用 `grep -n "^- \[ \]"` 定位未答项，**不要整读**
   - 本轮答掉的问题：`- [ ]` 改 `- [x]`，答案写在 `答：` 后面；**不删除已答条目**，历史是决策记录
   - 本轮新产生的、需要后端拍板的问题：追加到「待后端确认」，每条带日期 / 提问方 / 具体到文件行号或端点的上下文 / 明确的问题
   - 契约本身的变更不写这里 —— 直接改后端 `docs/api_spec.yaml`
9. **commit**：`type: 描述`（type 取 feat/fix/refactor/docs/test/chore/perf/ci）。**不带 `Co-Authored-By`**（`~/.claude/settings.json` 的 `includeCoAuthoredBy: false` 已全局关闭，不要手动加回来）
10. **push**

> 第 9–10 步由 Stop 钩子 `scripts/hooks/stop-checklist.mjs` 强制：**本轮写过的文件没提交**或
> **领先 origin** 时拦住本次停止并列出欠账。三条约束让它不至于变成噪音：
> - `stop_hook_active` 兜底，一次停止只拦一次 —— 用户说「先不提交」时回一句说明再停即可，不会死循环
> - 同一份欠账（相同路径集合 + 相同领先数）只提醒一次，签名存 `.git/aidrun-stop-checklist-seen`。
>   别人没写完的脏文件长期躺着时不会每轮都叫；欠账内容变了才重新叫
> - **欠账只算本轮 Edit/Write 写过的路径**（从 transcript 取，`scripts/hooks/transcript.mjs`）。
>   并行会话或同事在改的脏文件降级为提示；调研落盘同理，会去**本轮会话内的所有分支**找提交，
>   不只看工作树和 HEAD —— 单开 docs 分支提交调研是常态，只看 HEAD 会每轮误报一次
>
> handoff（第 8 步）**不作独立触发条件**，只在已有欠账时附带提醒 —— 纯客户端改动本就不该投递，
> 拿「提交晚于 handoff」当触发会让每次工具链提交都误报。什么该投递见记忆 `handoff-upkeep-workflow`。
>
> 自测 `scripts/validate-stop-checklist.mjs`（9 条，CI 与 pre-push 都跑）。
>
> 这条从「用户每轮口头提醒」升级成钩子，走的是 §1.3。

## 11. 验证命令

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道；脚本会先探活，统计只认 result bundle 不认日志）
# ⚠️ 默认**不要**这样裸跑全量，先看下面「跑多大范围」
scripts/device-test.sh

openspec validate --all --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs    # 路径级：前端调的每条路径都在契约里
node scripts/validate-golden-corpus.mjs    # 语音黄金语料 vs 前端镜像清单
node scripts/validate-error-codes.mjs      # 前端 ErrorCode 枚举 vs 后端 ErrorCode.java
node scripts/validate-voice-intent-words.mjs  # 确认轮本地直通表 vs 后端 VoiceSlotParser 的 INTENT_* 正则
scripts/production-readiness-check.sh      # 需 AIDRUN_* 环境变量，见 aidrun-ship-check
scripts/dual-device-validation.sh
```

中间四条（spec-coverage / golden-corpus / error-codes / voice-intent-words）要读后端仓库。
装一次本地 pre-push 钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。
CI（`.github/workflows/verify.yml`）跑编译门禁 + 规格校验，但**跑不了真机 XCTest**。

### 跑多大范围：默认只跑覆盖本次改动的 suite，不是全量

全量约 10 分钟、会超 Bash 600s 上限、还会撞上脚本的 preflight watchdog 反复被掐。
**默认做法**：先查哪些用例真的碰了你改的东西，只跑那几个 suite。

```bash
# ① 先定范围（把改动涉及的类型/方法名列进去）
python3 - <<'EOF'
import os, re
PATTERN = r'(BookingDurationOption|expectedDurationMinutes|makeCreateOrderRequest)'  # 换成你改的符号
for root, _, fs in os.walk('blindRunTests'):
    for f in (x for x in fs if x.endswith('.swift')):
        p = os.path.join(root, f)
        n = sum(1 for l in open(p).read().split('\n') if re.search(PATTERN, l))
        if n: print(f'{f}: {n} 处')
EOF

# ② 只跑命中的 suite
scripts/device-test.sh -only-testing:blindRunTests/VoiceOrderWizardTests \
                       -only-testing:blindRunTests/blindRunTests
```

**什么时候才必须全量**——只有一条判据：**改的东西是全 App 唯一的出口 / 共享单例 / 全局配置**，
所有调用方都从它身上过。例如 `SystemSpeechAudioSession`（每个用麦克风的地方都走它）、
`APIClient`、`AppState`。这类改动的影响面按符号搜不出来，必须全量。

反过来，「改了一个 view model 的一个字段」「加了一条解析规则」不属于这类，按符号搜到的 suite
就是完整覆盖面。**命中数只有 1 且是无关字面量的文件要看一眼再决定跳过**，别只看数字。

> 2026-08-06 立此条：同一天里全量被反复跑了 5 次，其中 4 次的结论在第 1 次就已经拿到，
> 后面纯粹是在跟脚本的 watchdog 较劲。用户两次指出这件事，走 §1.4。
>
> **零执行不是通过。** `passed=0 failed=0` 一律当失败查——设备锁屏、`-only-testing` 名字打错、
> 测试目标没编出来都会长这样：命令回来了、看起来一切正常，但一条断言都没跑。
> 脚本对这种情况有硬失败，别绕过它。

### 读后端仓库的那 5 条门禁在哪跑（2026-08-12 改口径，别再按旧的双推推导）

契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料 / 确认轮词表这 5 条需要读后端私有仓库，
跑在**两个地方**：

| 位置 | 这 5 条 | 说明 |
|---|---|---|
| `Jayden23018/blind-run-ios`（`origin`，**主线**）| ✅ 真跑 | 配了 `BACKEND_REPO_TOKEN`（fine-grained PAT，只读 `blind-run-backend`） |
| 本地 pre-push | ✅ 真跑 | 读 `../demo` 的 `origin/main`，装钩子后每次 push 自动 |

**`JerryZhao-1/blind-run-ios` 自 2026-08-12 起只是 `upstream`，不再是投递目标。** 分支不往那边推、
PR 也不往那边开。它的 CI 配不上 secret（我们不是 admin），这 5 条在那边是 warning 空过 ——
**上游 CI 绿 ≠ 契约对过了**。要取上游的新提交：`git fetch upstream`。

**主线仓库的既定配置**（改动前先知道，别当成异常）：

- 默认分支是 `integrate/swift-migration`，不是 `main` —— `workflow_dispatch`
  和 `schedule` 都只认默认分支，而 `main` 上没有 `verify.yml`。手动触发：
  `gh workflow run verify.yml --repo Jayden23018/blind-run-ios --ref integrate/swift-migration`
- `schedule` 每天 09:17（北京）跑一次。它抓的是 **push 触发天生抓不到的那类：你 push 之后
  后端才改契约**。
- **CI 红在 `Checkout backend contract`（403）= PAT 过期了**，不是代码坏了。
  重建 PAT 后 `gh secret set BACKEND_REPO_TOKEN --repo Jayden23018/blind-run-ios`。
- GitHub 会把连续 60 天无活动仓库的定时任务停掉。长期没推东西时留意一下。

每台机器装一次钩子即可，不再需要配双推（旧机器重跑本脚本会清掉遗留的双推配置）：

```bash
scripts/install-git-hooks.sh
```

这 5 条读的契约**取自后端仓库的 `origin/main`**（`git show origin/main:docs/api_spec.yaml`
落到临时文件），不是 `../demo` 的工作区文件 —— 工作区是共享 checkout，随时停在特性分支
或带着同事未提交的 WIP，而 CI 是从后端默认分支拉契约的。所以 `../demo` 当前在哪个分支、
脏不脏，都不影响门禁结论。

确实要拿未合并的后端改动验证 iOS 侧：`AIDRUN_ALLOW_BACKEND_DRIFT=1 git push` 改读工作区文件
（或用 `AIDRUN_API_SPEC=` / `AIDRUN_GOLDEN_CORPUS=` / `AIDRUN_BACKEND_ERROR_CODES=` /
`AIDRUN_BACKEND_VOICE_PARSER=` / `AIDRUN_BACKEND_VOICE_SERVICE=` 逐个指定）。
此时「生成代码与契约不同步」**不构成提交理由** —— 那份契约不是上游的，提交重新生成的结果
等于把别人的 WIP 烘进你的 PR。钩子在这条路径上会自己说明，并给出 `git checkout --` 的还原命令。

> ⚠️ **这只管 pre-push。** 手动跑 `node scripts/validate-*.mjs` 仍然默认读 `../demo` 工作区 ——
> 2026-08-12 因此把一份**正确**的语料镜像改动判成了伪造（后端当时停在特性分支，语料 96 条而
> `origin/main` 已 101 条），差点据此删掉。手动跑之前自己导出真契约：
> `git -C ../demo show origin/main:docs/voice-golden-corpus.json > /tmp/c.json` 再传进去。
> 详见 `docs/review/frontend-backend-alignment-review-20260812.md` §B1。

> 第 5 条 `validate-voice-intent-words.mjs` 是 2026-08-10 加的：确认轮改成「本地直通 + 后端兜底」
> 之后，同一句话由两处判定，本地表里出现一个后端判成**别的**意图的词就会让有网/断网行为分叉。
> 加它的直接起因是「再说一次」——前端判「重说」（清空整句）、后端判 `REPEAT`（只重念）。

契约 fixture（真实响应回归，见 `blindRunTests/ContractFixtureTests.swift`）：

```bash
node scripts/capture-fixtures.mjs            # dry-run，只列要打的只读端点
node scripts/capture-fixtures.mjs --write    # 真实采集并脱敏落盘
```

**编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**

## 12. 联网调研只落一个地方

唯一位置 `docs/research/`，唯一索引 `docs/research/INDEX.md`。规则三条：

1. **开搜前整份读 INDEX.md**，按「复核触发条件」列判旧结论还作不作数。没触发就直接用，不要重搜。
2. 新一轮只搜**表里缺的那一段**，不是把整个问题重来一遍。
3. 调研完落 `docs/research/{topic}-{YYYYMMDD}.md`，**并回写 INDEX.md 一行**（日期 / 问题 /
   一句话结论 / 复核触发条件 / 报告，五列齐全）。不回写等于没做 —— 下次搜不到，原样重跑。

被否掉的方案同样留一行：「试过 X 因为 Y 放弃」跟「选了 Z」一样值钱，且更容易被忘。

> 强制在 `scripts/hooks/research-log.mjs`（走 §1.1 + §1.3）：PreToolUse 在联网工具调用前把整份索引
> 灌回给模型（第 1 条）；Stop 钩子发现本轮联网过但 `docs/research/` 一个字节没动就拦（第 3 条）。
> 只是查一个 API 签名、不构成调研的，回一句说明再停。
> 自测 `scripts/validate-research-log.mjs`（7 条，CI 与 pre-push 都跑）。
>
> 位置约定本来就写在 skill `tech-decision-research` 里，但 skill 不被显式调用就不生效 ——
> 于是 `docs/research/` 建了两份报告却一直没有索引。这条是把约定接上强制。

## 13. 成体系的 review 也只落一个地方

唯一位置 `docs/review/`，唯一索引 `docs/review/INDEX.md`，规则与 §12 同构：**开新 review 前整份读索引**，
按「复核触发条件」判旧结论作不作数；review 完落 `docs/review/{topic}-{YYYYMMDD}.md` 并回写索引一行。

与 §12 的分工：`docs/research/` 记「外面是怎么做的」（联网事实，带来源与核实日期）；
`docs/review/` 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。
一次 review 引用一次 research 是常态，反过来不成立 —— 竞品事实不要写进 review，两处都写会漂移。

> ⚠️ 这条**没有 hook 强制**，`research-log.mjs` 只管联网调研。漏过第二次就按 §1.1 落成守卫。
>
> 2026-08-12 立此条：`frontend-backend-alignment-review-20260812.md` 原本躺在 `docs/` 根目录，
> 与 20 个同级文档混在一起 —— 下一次 review 既不会先读它，也不会挨着它落盘。已迁入 `docs/review/`。
