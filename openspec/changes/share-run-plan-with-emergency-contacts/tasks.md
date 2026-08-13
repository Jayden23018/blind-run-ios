# Tasks

## 1. 契约投递

> ⚠️ 当前**投不了**：`demo/docs/handoff.md` 是后端同事的未提交工作区（` M`），
> 现在写会跟他的 WIP 打架。等 `feat/trip-share-link` 合入 `main` 后立即投递。
> 答案已经定下来，写在 `proposal.md`「回后端的两个问题」一节，届时原样搬过去。

- [ ] 1.1 答后端问题①：明示告知的形态 → 首次全屏引导页 + 之后每次简短确认，
      同意按用户 + 告知版本记录。
- [ ] 1.2 答后端问题②：入口在盲人端订单状态页，非终态全给（含 `PENDING_MATCH`），
      终态隐藏而非禁用。
- [ ] 1.3 提问：`OrderDetailResponse` 无志愿者身份字段 —— 分享页你们已给掩码姓名（`李*`），
      但短信降级路径拿不到它，能否在订单详情里补同一口径的标识。
- [ ] 1.4 提问：`expiresAt` 是绝对过期还是随订单生命周期延长？决定客户端要不要做续期提示。
- [ ] 1.5 提问：志愿者手机号能否写进发给第三方的短信（默认不写，与你们「志愿者是第三方」同一口径）。

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
- [ ] 3.3 **挂载点等契约**：`POST` / `DELETE /api/orders/{id}/share` 合入 `main` 后，
      在实时分享入口前接上 `RunPlanShareConsentStep`，同意后才发请求。
      拿到 `shareUrl` 原样丢进系统分享面板（**不要**重新拼链接把 fragment 里的 token 挪到 query）。
- [ ] 3.4 **挂载点等契约**：`DELETE /share` 的「停止分享」入口，以及 404 / 410 的文案分开
      （404 = 链接不存在，让家属跟分享的人核对；410 = 曾经有效但已结束）。

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
- [x] 4.4 编译门禁 `build-for-testing` —— **TEST BUILD SUCCEEDED**。
- [x] 4.5 `validate-guard` / `validate-docs` / `validate-spec-coverage`（读后端 `origin/main`
      契约）/ `openspec validate --strict` 全过。

## 5. 收尾

- [ ] 5.1 真机 `111` 开 VoiceOver 走一遍：短信按钮可达、hint 说清「需要你自己点发送」、
      composer 关闭后**听得到**结果播报；同意页三条告知右滑一次一条、拒绝按钮找得到。
- [ ] 5.2 低视力档位（AX3 以上字号 + 深色模式）看一眼同意页不裁切。
- [ ] 5.3 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [ ] 5.4 后端合入后：投 handoff（第 1 节五条）、接上 3.3 / 3.4、撤掉本文件这条说明。
