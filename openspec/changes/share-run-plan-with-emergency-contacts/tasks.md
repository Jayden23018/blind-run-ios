# Tasks

## 1. 契约投递（与实现并行，结论到之前不改本变更的行为）

- [ ] 1.1 投 handoff「待后端确认」：**实时行程分享的完整契约**——令牌签发端点、免登录只读页、
      失效时机（对标产品绑行程生命周期，不用固定 TTL）、联系人上限、跑后只读页内容。
      注明这是本方向的终局，本次交付的静态告知是它的真子集。
- [ ] 1.2 投 handoff：`OrderDetailResponse` **无志愿者身份字段**（只有 `volunteerPhone`），
      请补一个可对外披露的标识（姓氏 + 平台编号）。附本变更 `design.md` D5 的理由。
- [ ] 1.3 投 handoff：志愿者手机号能否写进发给第三方的短信，需要志愿者侧授权口径。

## 2. 实现

- [ ] 2.1 新建 `blindRun/Shared/RunPlanShareMessage.swift`：
      纯函数 `compose(order:) -> String?` + 状态门控 `canShare(status:)`（穷举 switch，见 D2）。
      **不 import UIKit**，保证可单测。
- [ ] 2.2 新建 `blindRun/Shared/MessageComposePresenter.swift`：
      `UIViewControllerRepresentable` 包 `MFMessageComposeViewController`，
      呈现前查 `canSendText`，`didFinishWithResult:` 回调把 sent/cancelled/failed 交给调用方。
- [ ] 2.3 `blindRun/BlindRunner/BlindOrderStatusView.swift` 加入口：
      按 D2 的四态渲染「把这次行程告诉家人」，收件人取主紧急联系人，
      无联系人时引导到紧急联系人管理页（不隐藏按钮）。
      按 D4 在回调里播报，走既有 `SpeechService`。
- [ ] 2.4 **按 `AGENTS.md` §1.1 落守卫**：`scripts/hooks/guard.mjs` 加一条规则，
      拦住发布产物里出现「已通知家人 / 家人已收到 / 已送达」这类完成时态措辞
      （与既有 SOS 文案守卫同一族）。同步给 `scripts/validate-guard.mjs` 加正反用例。

## 3. 测试

- [ ] 3.1 `blindRunTests/RunPlanShareMessageTests.swift`（纯单测，不需要真机）：
      - 四个允许状态各返回非 nil；`PENDING_MATCH` / `COMPLETED` / `CANCELLED` /
        `REMATCHING` / `NO_VOLUNTEER` 各返回 nil
      - `endAddress == nil` 时**正文一个「终点」字样都没有**（D5 的硬口径，这条是回归的重点）
      - `plannedStart` / `plannedEnd` / `startAddress` 各自为 nil 时只省略该项，不整条崩
      - 正文**不含** `volunteerPhone`、`blindPhone`、`specialNotes`、`visionLevel`
- [ ] 3.2 `blindRunTests/` 加一条断言：三条播报文案不含「已通知 / 已收到 / 已送达」。
- [ ] 3.3 跑**收窄范围**的真机测试（按 `AGENTS.md` §11「跑多大范围」，本变更不碰全局单例，
      不需要全量）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/RunPlanShareMessageTests \
                             -only-testing:blindRunTests/blindRunTests
      ```
      `passed=0` 一律当失败查。
- [ ] 3.4 `node scripts/validate-guard.mjs` 与 `node scripts/validate-spec-coverage.mjs`
      （本变更不新增 `/api/` 路径，coverage 应当零变化——若变了说明拼错了路径字面量）。

## 4. 收尾

- [ ] 4.1 真机 `111` 上开 VoiceOver 走一遍：按钮可达、hint 说清「需要你自己点发送」、
      composer 关闭后**听得到**结果播报（D4 的核心，看不到 sheet 收起）。
- [ ] 4.2 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [ ] 4.3 同步 handoff（第 1 节三条），commit，push，开 PR。
