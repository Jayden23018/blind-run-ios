# ⛔️ 本仓库不再维护 WebSocket 协议文档

唯一源：`/Users/mac/Downloads/demo/docs/websocket-protocol.md`（后端仓库 `blind-run-backend`）

详见 [07-api-contract-MOVED.md](07-api-contract-MOVED.md)。历史文件归档在 `_archive-websocket-protocol.md.bak`。

## ⚠️ 归档文件里已知的错误（不要照抄）

- `SEPARATION_ALERT` —— **后端没有这个 WS type**。走散告警实际是
  `type=APP_NOTIFICATION` + `eventType=ESCORT_DISTANCE_ALERT`
- 缺 `ESCORT_SIGNAL_LOST`（信号缺失兜底）、`PROXIMITY_ALERT`（邻近感知）的 eventType 名
