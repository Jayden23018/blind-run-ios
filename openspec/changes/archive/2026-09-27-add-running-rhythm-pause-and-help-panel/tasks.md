## 1. 数据层

- [x] 1.1 `OrderDetailResponse` 加 `run`（可选解码，未知信号降级）与 `blindSurname` / `volunteerSurname`；`replacingStatus` 带上
- [x] 1.2 `OrderServing` 加 `sendRhythm` / `pauseRun` / `resumeRun`，`OrderEndpoint` 三条路径，Mock 实现
- [x] 1.3 `WSLocationUpdateMessage.batteryLevel`，跑者角色才带
- [x] 1.4 四个新 `eventType` 进订单刷新；`RUN_RHYTHM` 不进横幅

## 2. 陪跑员跑步页

- [x] 2.1 节奏卡 / 信号卡（纯函数呈现 + 8 秒高亮 + 5 分钟过期）
- [x] 2.2 信号到达判定（首载与 >30 秒不提醒）+ 触感 + announcement + 语音播报
- [x] 2.3 耳机语音播报开关（`@AppStorage`，默认关）+ 每公里播报
- [x] 2.4 提示条三档与优先级
- [x] 2.5 暂停灰条 + 「继续陪跑」+ 暂停时结束按钮改次要样式
- [x] 2.6 求助面板（暂停 / 联系客服 / 长按 3 秒紧急求助 + 锁定文案确认框）；导航栏「求助」改开面板

## 3. 跑者端

- [x] 3.1 三个 64pt 节奏按钮 + 成功 TTS + 429 / 失败文案

## 4. 验证与收尾

- [x] 4.1 单测：呈现纯函数、到达判定、提示条优先级、电量编码、解码降级
- [x] 4.2 更新 `AccessibilityAuditTests` 陪跑员求助入口用例 + 新增面板用例
- [x] 4.3 真机跑覆盖改动的 suite（含 `EmergencySOSTests` 与相关 `AccessibilityAuditTests`）—— 单测 83/0，陪跑员跑步页 UI 6/0（含横屏）
- [x] 4.4 security-reviewer 复核求助面板（A1 暂停状态闸 + 面板随状态收起、A2 删「并告知客服」已修）
- [x] 4.5 `AGENTS.md` §6、`docs/ui/design-direction.md`（V13）同步
- [x] 4.6 后端 BE-1 / BE-2 合并后按实际契约对齐推定（design.md 表），再推送 —— 全部一致，补接 `delivered`
