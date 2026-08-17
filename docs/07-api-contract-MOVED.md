# ⛔️ 本仓库不再维护 API 契约

**唯一契约源在后端仓库：**

| 契约 | 路径 |
|------|------|
| REST（OpenAPI 3.1，77 operations） | `blind-run-backend/docs/api_spec.yaml` |
| WebSocket 消息协议 | `blind-run-backend/docs/websocket-protocol.md` |
| 端点/DTO/WS 综合说明（按 feature 组织） | `blind-run-backend/docs/frontend-guide.md` |

本机路径：`/Users/mac/Downloads/demo/docs/`

## 为什么

2026-07-28 前，本仓库维护了一份独立的 `07-api-contract.openapi.yaml`（4210 行）和
`websocket-protocol.md`（606 行）。两份契约漂移，已造成实际缺陷：

- 前端按本地文档实现 `type = "SEPARATION_ALERT"` 监听走散告警，
  **后端从不发送这个 type**（实际是 `type=APP_NOTIFICATION` + `eventType=ESCORT_DISTANCE_ALERT`）
- 本地文档缺 `ESCORT_SIGNAL_LOST`、`PROXIMITY_ALERT`、`GET /api/notifications/since`、
  `POST /api/devices/apns`、`GET /api/orders/{id}/track` 等 7 个后端已实现的能力

后端是实现方，谁实现谁定义。历史文件归档在同目录 `_archive-*.bak`，仅供追溯，**不要参照它写代码**。

## 怎么用

写前端代码前，在本仓库启动 Claude Code 时挂载后端目录：

```bash
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir /Users/mac/Downloads/demo
```

发现契约有问题、或需要后端配合改动 → 写进 `/Users/mac/Downloads/demo/docs/handoff.md`。
