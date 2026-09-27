# 实时活动「已结束」样式能不能按 activityState 画 · push token 在免费团队下能不能拿到（2026-09-26）

> 🔄 **2026-09-28 补记**：本报告原在未推送分支 `feat/guide-run-live-activity` 里（锁屏汇合卡的一版实现，与 PR #231 重复，已弃用、以 #231 为准），清理 worktree 时单独救出。第 3 条已由 #231 真机实测证实（iPhone 16 Pro / iOS 26.6.1）：`pushType: .token` 抛 `SessionCore.PermissionsError Code=3`，`pushType: nil` 正常。


背景：issue #213 / 后端 Jayden23018/blind-run-backend#434 要求锁屏「已结束」样式按 `activityState == .ended` 画。

## 结论

1. **widget 视图拿不到 `activityState`。** 核实方式：本机 Xcode 的 iOS 26.2 SDK
   `WidgetKit.framework/.../arm64e-apple-ios.swiftinterface:314-322`，`ActivityViewContext`
   只有 `activityID` / `attributes` / `state` / `isStale` 四个公开成员；`activityState` 与
   `activityStateUpdates` 只在 `ActivityKit` 的 `Activity`（App 进程）上
   （`ActivityKit.swiftinterface:90-93`）。
   ⇒ 视图里唯一能用的运行时标志是 `context.isStale`。方案：后端在 `end` 前先推一条带
   `stale-date = 现在` 的 update，视图按 `isStale` 画结束样式。
2. **`stale-date` 的官方说明写在 update 上。** Apple《Starting and updating Live Activities with
   ActivityKit push notifications》（JSON 版 `developer.apple.com/tutorials/data/documentation/activitykit/
   starting-and-updating-live-activities-with-activitykit-push-notifications.json`，2026-09-26 抓取）原话：
   "To mark a Live Activity as outdated with an update, optionally set the `stale-date`."
   同页再次确认 "the system always decodes JSON payloads for Live Activity updates using its default
   encoding strategies"（与 #434 的 2001 纪元秒结论一致）。
   **`stale-date` 放在 `end` 事件里是否生效，文档没写、也没实测** —— 所以约定用一条单独的 update。
3. **免费个人团队签名拿不到远程推送 token。** 本机三份描述文件（`~/Library/Developer/Xcode/UserData/
   Provisioning Profiles`）都是 `iOS Team Provisioning Profile`、有效期 7 天，entitlements 里没有
   `aps-environment`。`Activity.request(pushType: .token)` 在这种签名下的行为未在真机验证；
   代码按「抛错就退回 `pushType: nil`」处理。

## 抓取通道备注

`WebFetch` 对 developer.apple.com 页面只拿到标题（页面靠 JS 渲染）；firecrawl 当天 token 失效。
**用 `developer.apple.com/tutorials/data/documentation/<path>.json` 直接 curl 拿 DocC JSON 最可靠。**

## 复核触发条件

Apple 给 `ActivityViewContext` 加 `activityState`；APNs 文档写明 `end` 事件支持 `stale-date`；
项目换成付费开发者账号（第 3 条要真机重验）。
