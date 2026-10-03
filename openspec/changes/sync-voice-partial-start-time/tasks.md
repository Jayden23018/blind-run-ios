# Tasks

## 1. 契约与模型

- [x] 1.1 `scripts/sync-api-client.sh` 重新生成 `Packages/AidRunAPI`（从后端 `origin/main` 取契约）；`report-drift-fields` 报 `partialStartTime` 两处 ❌ 即本变更要补的
- [x] 1.2 `VoiceOrderModels.swift` 新增 `VoicePartialStartTime`（`date` / `period` 都存字符串；`period` 不做枚举，未知值原样回传）与 `isEmpty`
- [x] 1.3 `ParseVoiceOrderResponse` 与 `VoiceSlotSnapshot` 加 `partialStartTime`；`slotSnapshot` 带上，空壳不带；`replacingStartPlace` 原样保留

## 2. 向导

- [x] 2.1 `VoiceOrderWizard.confirmRoundSnapshot`（起点回落设备位置时**手工拼快照**的那一处）补上 `partialStartTime`

## 3. Mock 对齐后端 2026-10-03 时段换算

- [x] 3.1 `timeLikeRegex` 加「凌晨」
- [x] 3.2 `clockTime`：中午 一~四点 +12，凌晨 十二点 = 0 点（对齐后端 `to24Hour`）

## 4. 测试

- [x] 4.1 黄金语料镜像补 10 条（START_TIME/regex 9、ADDRESS/llm 1）；`node scripts/validate-golden-corpus.mjs <后端 origin/main 语料>` 125 条全部一致
- [x] 4.2 新增 6 条用例：契约示例解码并回传、未知 period 原样回传、空值不上线、挑候选保留、**补设备位置的手工快照不丢**、响应已有起点时照常带
- [ ] 4.3 真机跑 `VoiceOrderWizardTests`，贴 `passed=N failed=0`
- [ ] 4.4 `xcodebuild build-for-testing`（device SDK）编译通过

## 5. 交接

- [ ] 5.1 PR 合并后在后端 issue #508 评论：已接入、Mock 不产出该字段、`parseFreeform` 的 `ttsText` 播报条件待产品拍板；再 close
