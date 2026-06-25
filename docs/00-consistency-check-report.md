# AidRun iOS Frontend Consistency Report

## 检查范围

- `AGENTS.md` 与根 `README.md`
- `docs/01-10`、OpenAPI、WebSocket 和 UI 交接文档
- `openspec/changes/remove-local-backend-use-cloud-only/`
- iOS 环境配置、APIClient、WebSocket、单元测试和 UI 测试

## 当前结论

- 本仓库仅包含并维护原生 iOS 前端，不包含服务端实现、数据库配置或服务端部署工具。
- Mock 仅用于进程内前端调试和自动化测试，不发起网络请求，也不能作为上线验收依据。
- 所有真实 HTTP 请求固定使用 `http://47.114.113.171`。
- 所有真实 WebSocket 连接固定使用 `ws://47.114.113.171`。
- `docs/07-api-contract.openapi.yaml` 是 HTTP API source of truth；`docs/websocket-protocol.md` 是 WebSocket source of truth。
- Debug 可切换 Mock / Demo Cloud；Demo 和 Production 构建固定 Demo Cloud。
- 上线验收必须在真机 `111` 和 `iPad Pro (2)` 上覆盖真实高德地图、真实后端 UI smoke 和后端 E2E。

## 一致性要求

- 不得新增可配置的其他真实服务器地址。
- 不得在仓库内新增服务端源码、数据库、服务端构建脚本或部署说明。
- API 模型、错误码和状态流转必须以云端契约及 `AGENTS.md` 为准。
- 旧 Flutter 仅可作为 UI 行为参考。

## 校验命令

```bash
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
node scripts/validate-docs.mjs
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

云端 E2E 依赖外部服务可用性，并会创建/取消测试订单；失败项应与 iOS 编译和 Mock 回归结果分开报告。
