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

任何一个**已经犯过第二次**的错误，必须落到下面四者之一，**不许只写进文档**：

1. 能被静态检查抓到 → `scripts/hooks/guard.mjs` 加一条守卫
2. 能被运行时检查抓到 → 加一条测试（优先 `blindRunTests/Fixtures/` 的真实响应回归）
3. 能被「该做没做」抓到 → 加进 Stop 钩子 `scripts/hooks/stop-checklist.mjs`
4. 三者都不能（纯语义认知）→ 写进项目记忆，并在本文件留一行索引

只写文档不算完成。文档挡不住重复犯错，这条规则的存在就是因为它已经被证明挡不住。

**「反复查」和「反复错」同等对待。** 同一个事实如果第二次还要重新 grep / 重读文件才能确定
（某个函数在哪、某个脚本叫什么、某个字段的真实类型），那不是记性问题，是事实没落地：
就地把它写进本文件或对应 skill，带上 `文件路径:行号`。上面 §1.1 那条 `guard.sh` → `guard.mjs`
就是例子 —— 文件早改名了，规则里没跟，于是每次都要重查一遍才发现引用是错的。

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

## 9. 冻结文件

**整文件冻结**：`Podfile` —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。

**行级冻结**：`blindRun.xcodeproj/project.pbxproj` —— 文件可以改（例如加 SPM 依赖），但改动内容**不得触及 `DEVELOPMENT_TEAM`**。写死的 `R6PH2TFB3Q` 是原开发者的团队号，命令行传 `DEVELOPMENT_TEAM=ZW39BS8NXT` 覆盖。

**任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无 arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，行尾加 `guard:allow excluded-archs`。

> 2026-08-06 从整文件冻结改为行级。核对后发现原先给的两条理由只有一条落在 pbxproj 上（`DEVELOPMENT_TEAM`，12 处）；`EXCLUDED_ARCHS` 在 pbxproj 里出现 **0 次**，它只存在于 `Podfile:36`。整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」依赖人记得加回来 —— 第 1 节说的就是这种挡不住重复犯错的做法。
>
> 守卫在 `scripts/hooks/guard.mjs`，自测在 `scripts/validate-guard.mjs`（8 条用例，CI 与 pre-push 都跑）。

## 10. 工作流

**开工前**

1. 先读 `AGENTS.md`
2. 再读相关 docs 与 OpenSpec
3. 判一次这活要不要派 subagent —— 判定表在全局 `~/.claude/CLAUDE.md` 的「委派」节，**本文件不留副本**（理由同 §7：两份会漂移）。一句话版：定位/摘要/读日志外包，设计与编辑自己干

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

> 第 8–10 步由 Stop 钩子 `scripts/hooks/stop-checklist.mjs` 强制：工作树脏、领先 origin、或
> handoff 比最后一次提交还旧时，会拦住本次停止并列出欠账。每轮只拦一次（`stop_hook_active` 兜底），
> 所以用户说了「先不提交」时，回一句说明再停即可，不会死循环。
>
> 这条从「用户每轮口头提醒」升级成钩子，走的是 §1.3。

## 11. 验证命令

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道；脚本会先探活并按小写 `Test case` 统计）
scripts/device-test.sh

openspec validate --all --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs    # 路径级：前端调的每条路径都在契约里
node scripts/validate-golden-corpus.mjs    # 语音黄金语料 vs 前端镜像清单
node scripts/validate-error-codes.mjs      # 前端 ErrorCode 枚举 vs 后端 ErrorCode.java
scripts/production-readiness-check.sh      # 需 AIDRUN_* 环境变量，见 aidrun-ship-check
scripts/dual-device-validation.sh
```

后三条要读后端仓库。装一次本地 pre-push 钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。
CI（`.github/workflows/verify.yml`）跑编译门禁 + 全部规格校验，但**跑不了真机 XCTest**。

契约 fixture（真实响应回归，见 `blindRunTests/ContractFixtureTests.swift`）：

```bash
node scripts/capture-fixtures.mjs            # dry-run，只列要打的只读端点
node scripts/capture-fixtures.mjs --write    # 真实采集并脱敏落盘
```

**编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**
