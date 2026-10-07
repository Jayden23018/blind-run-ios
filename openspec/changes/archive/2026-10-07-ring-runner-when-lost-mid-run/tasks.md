## 1. 跑者端

- [x] 1.1 `RunnerRingRequest.Kind`：由 eventType 决定（`RUNNER_RING` / `RUNNER_RING_LOST`），其余 eventType 不响
- [x] 1.2 `RunnerRingCopy` 按种类取标题、说明、读屏标签与兜底朗读；遮罩接收种类
- [x] 1.3 协调器两个 eventType 都走响铃路由；UI 测试接缝 `AIDRUN_UI_TEST_RUNNER_RING=lost`

## 2. 陪跑员端

- [x] 2.1 跑步中求助面板加「让{名}的手机响起来」一行，`ringingUntil` 前显示「正在响铃…」不可点
- [x] 2.2 跑步页显示响铃回执；订单状态变化时清回执
- [x] 2.3 `DECISIONS-v2.md` V5 / V12 与 `docs/ui/mockups/INDEX.md` 记录推翻来源

## 3. 验证

- [x] 3.1 单测：种类判定、走散文案、协调器路由、缺 `until` 回落、状态变化清回执
- [x] 3.2 真机跑覆盖改动的 suite（单测 + 两条 UI 用例），按 result bundle 核对执行数
