# Tasks

## 1. 契约投递

> 2026-08-13：后端 `fdbc4ee`（#86）已合入 `origin/main`，三个端点在契约里，投递不再受阻。

- [ ] 1.1 答后端问题①：明示告知的形态 → 首次全屏引导页 + 之后每次简短确认，
      同意按用户 + 告知版本记录。
- [ ] 1.2 答后端问题②：入口在盲人端订单状态页，非终态全给（含 `PENDING_MATCH`），
      终态隐藏而非禁用。
- [ ] 1.3 提问：`OrderDetailResponse` 无志愿者身份字段 —— 分享页你们已给掩码姓名（`李*`），
      但短信降级路径拿不到它，能否在订单详情里补同一口径的标识。
- [ ] 1.4 提问：`expiresAt` 是绝对过期还是随订单生命周期延长？决定客户端要不要做续期提示。
- [ ] 1.5 提问：志愿者手机号能否写进发给第三方的短信（默认不写，与你们「志愿者是第三方」同一口径）。
- [ ] 1.6 提问（新）：`OrderDetailResponse` 里没有分享状态字段，且 `/share` 只有 `POST` / `DELETE`
      没有 `GET` —— 客户端判断「这一单是不是正在分享」只能靠本地记录，
      重装或换设备后「停止分享」的入口就没了，而链接在服务端还活着。
      能否在订单详情补 `shareActive` / `shareExpiresAt`？补上后客户端可以删掉
      `RunPlanLiveShareStore`。

## 2. 静态告知（降级路径）

- [x] 2.1 `blindRun/Shared/RunPlanShareMessage.swift`：文案集中 `RunPlanShareCopy` +
      纯函数 `compose(order:)`，不 import UIKit。
      **与初版计划的差异**：状态门控没有放在这个文件，而是作为 `offersRunPlanShare` 放进
      `blindRun/Core/Models/OrderDisplayHelpers.swift` —— 与 `offersVolunteerCall` /
      `keepWaitingEndpoint` 同族，后端加状态时一个文件里一起编译报错。
- [x] 2.2 `blindRun/Shared/MessageComposeSheet.swift`：`UIViewControllerRepresentable` 包
      `MFMessageComposeViewController`，呈现前查 `canSendText`，coordinator 不自己 dismiss
      （交给 SwiftUI 的 `isPresented`，避免两边都关）。
- [x] 2.3 `blindRun/BlindRunner/BlindOrderStatusView.swift` 入口：非终态渲染次级按钮，
      收件人取主紧急联系人，三道门（先查设备能不能发、再查有没有联系人）。
      回调按 `didFinishWithResult:` 播报，成功走 `speak`、受阻走 `speakError`。
- [x] 2.4 **按 `AGENTS.md` §1.1 落守卫**。做的时候发现两个既有缺口，比原计划的「新加一条规则」更值得修：
      - `sos-copy` 的接收方词表是 `(联系人|家属|亲属)`，**没有「家人」** —— 本功能通篇用的
        正是这个称呼，等于整条从守卫旁边绕了过去。补词表比新加规则对：同一类缺陷换个称呼
        就能穿过去，说明词表本身是这条规则的薄弱面。
      - `scripts/validate-guard.mjs` 里 `sos-copy` **一条自测都没有**（28 条覆盖的是 pbxproj、
        架构排除、服务端地址）。规则躺了很久没人验过它拦不拦得住。补 6 条正反用例，
        并让 runner 支持 post 模式（内容级规则从磁盘读真实文件，此前 runner 硬编码只跑 `pre`）。
      - 全仓复扫确认新词表**不误伤既有代码**：唯一命中的 `SafetyModule.swift:88` 带
        `guard:allow sos-copy`（运营商回执支撑的唯一完成时分支）。
      - `node scripts/validate-guard.mjs` → 34 条全过。

## 3. 明示同意（不依赖契约，本次做完）

- [x] 3.1 `blindRun/Shared/RunPlanShareConsent.swift`：告知文案 `RunPlanShareConsentCopy`
      （三条各自独立）、`RunPlanShareConsentStore`（按用户 + 告知版本存，key 形如
      `runPlanShareConsent.v1.<userId>`）、`RunPlanShareConsentStep.next(hasGivenConsent:)` 纯函数。
- [x] 3.2 `blindRun/Shared/RunPlanShareConsentView.swift`：全屏告知页，三条各自是独立
      VoiceOver 焦点（该 `VStack` 上**不许**加 `children: .combine`），
      拒绝按钮与同意按钮同样大、同样整行铺满。
- [x] 3.3 接上 `RunPlanShareConsentStep`：首次走 `.fullScreenCover` 的全屏告知页，
      之后走 `.alert` 简短确认，同意后才 `POST /api/orders/{id}/share`。
      同意**在发请求之前**落盘 —— 反过来的话一次网络失败会让用户再看一遍全文告知，
      而他已经同意过了，重复告知是在消耗告知本身的效力。
      拿到 `shareUrl` 经 `RunPlanLiveShareMessage.compose` 原样丢进 `UIActivityViewController`
      （**不重新拼链接**，token 留在 fragment 里）。
- [x] 3.4 `DELETE /share` 的「停止分享」入口，以及跨重启的可撤销性：
      - 分享状态存 `RunPlanLiveShareStore`（单键，`AppStatePersistenceKeys` 里登出会清）。
        后端没有查询分享状态的端点，不持久化的话「随时可以停止」这句承诺会在杀 App 后静默失效。
      - **停止失败时不清本地状态**：链接可能还有效，把入口一起收走等于再也停不掉。
      - ⚠️ **原计划里的「404 / 410 文案分开」不归 iOS 管，已删除该项**：这两个码属于
        `GET /api/share/{token}`，那是免登录的家属分享页自己调的，页面（`share.html`）也是后端的。
        iOS 只调 `POST`（403/404/409）和 `DELETE`（403/404），全程见不到 410。
        映射的是 409 `SHARE_ORDER_ALREADY_FINISHED`（终态竞态），进 `ErrorCode`。
- [x] 3.5 短信降级路径改为**失败后才露出**，不再常驻：常驻会让读屏用户每次都多滑一个按钮，
      而它在实时分享可用时并不是用户想要的那条路。`canSendText` 为假时连降级入口都不给 ——
      摆出来等于把用户支上一条同样走不通的路。

## 4. 测试

- [x] 4.1 `blindRunTests/RunPlanShareMessageTests.swift`：状态门控穷举（非终态全给 /
      终态隐藏）、终点为空时正文一个字都不提终点、字段缺失逐项降级、正文不含双方手机号与健康信息、
      文案不含完成时态措辞。
- [x] 4.2 `blindRunTests/RunPlanShareConsentTests.swift`：首次走全屏 / 之后走简短确认、
      换账号不继承、bump 版本使旧同意失效、三条告知互不相同且各自完整、
      版本号与文案的字面绑定、拒绝反馈不带劝说。
- [x] 4.3 真机跑这两个 suite + 受影响的既有 suite（范围按符号搜 `blindRunTests` 定，
      本变更不碰全局单例，不需要全量）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/RunPlanShareMessageTests \
                             -only-testing:blindRunTests/RunPlanShareConsentTests \
                             -only-testing:blindRunTests/KeepWaitingTests \
                             -only-testing:blindRunTests/OrderEnumLeniencyDecodingTests
      ```
      **`passed=51 failed=0 skipped=0 result=Passed`**（iPhone 16 Pro）。
      逐 suite 核过日志确认不是零执行：`RunPlanShareMessageTests` 10 条、
      `RunPlanShareConsentTests` 9 条、`KeepWaitingTests` 15 条、
      `OrderEnumLeniencyDecodingTests` 17 条。
- [x] 4.3b `blindRunTests/RunPlanLiveShareTests.swift`（实时分享，16 条）：
      链接原样带出（fragment 未被改写、正文里没有 `?`）、文案不宣称送达、
      停止失败不说「已停止」、`canSendText` 为假时不提短信、`ShareLinkResponse` 缺
      `expiresAt` 不整条崩、409 有专属播报、单键分享状态（换单让位 / 重启仍在 / 登出会清）、
      Mock 端点幂等（重复 POST 同一条链接、DELETE 后重开是新链接、无链接时 DELETE 仍成功、
      终态返 409）。
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/RunPlanLiveShareTests \
                             -only-testing:blindRunTests/RunPlanShareConsentTests \
                             -only-testing:blindRunTests/RunPlanShareMessageTests \
                             -only-testing:blindRunTests/MockAPIClientErrorCodeTests
      ```
      **`passed=38 failed=0 skipped=0 result=Passed`**（iPhone 16 Pro）。
      逐 suite 核过日志确认不是零执行：`RunPlanLiveShareTests` 16 条、
      `RunPlanShareConsentTests` 8 条、`RunPlanShareMessageTests` 10 条、
      `MockAPIClientErrorCodeTests` 3 条。
- [x] 4.4 编译门禁 `build-for-testing` —— **TEST BUILD SUCCEEDED**。
- [x] 4.5 `validate-guard` / `validate-docs` / `validate-spec-coverage`（读后端 `origin/main`
      契约）/ `openspec validate --strict` 全过。

## 5. 收尾

- [ ] 5.1 真机 `111` 开 VoiceOver 走一遍：分享按钮可达、hint 说清「先说明再生成」、
      同意页三条告知右滑一次一条、拒绝按钮找得到；分享面板关闭后**听得到**「仍在分享中」；
      「停止分享」按钮在重开 App 后仍在。
- [ ] 5.2 低视力档位（AX3 以上字号 + 深色模式）看一眼同意页不裁切。
- [ ] 5.3 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [x] 5.4 后端合入后：接上 3.3 / 3.4 / 3.5，撤掉第 1 节的「投不了」说明。
      handoff 六条待投（后端仓库 `demo/docs/handoff.md`）。
