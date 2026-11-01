## Why

ICP 备案绑定域名。App 备案里填的后台域名必须是 App 实际连接的域名，而发布包写死裸 IP。负责人 2026-10-31 批准这次边界变更，原话：「批准改域名」（#621 评论），目标地址 `https://blindrun.culiu-tech.com`。

## What Changes

- **BREAKING** 所有真实 HTTP 改走 `https://blindrun.culiu-tech.com`，真实 WebSocket 改走 `wss://blindrun.culiu-tech.com`。旧地址不再是合法的真实服务端地址。
- 守卫 `server-addr` 的主机改成新域名，并改成主机全等比较。裸 IP 判据用的是子串匹配，换成域名后 `https://blindrun.culiu-tech.com.evil.net` 这类地址会穿过去。
- 守卫拦住写回旧 IP，包括没有 scheme 的裸字符串。
- 探针脚本的默认地址、单元测试断言、代码注释和仍在生效的文档同步到新地址。
- `Packages/AidRunAPI` 的生成代码等后端契约的 server 地址合进 `main` 后重新生成，不手改。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `cloud-only-api-environment`：固定的云端地址从 IP 换成备案域名，并且只接受加密 scheme。
- `backend-api-contract`：OpenAPI 契约唯一的 server 换成备案域名。
- `frontend-repository-boundary`：集成文档描述的外部服务地址换成备案域名。

## Impact

- **发布依赖**：`Jayden23018/blind-run-backend#885` 部署前，这个域名连不上服务器（2026-10-31 实测 `120.25.214.8` 的 80、443 不通）。合并前提是 `https://blindrun.culiu-tech.com/actuator/health` 返回 200，且 `wss` 能连上。PR 在此之前保持草稿。
- **旧构建**：已安装的构建继续连旧 IP。旧入口何时关闭由后端决定（`Jayden23018/blind-run-backend#885`），不在本变更范围内。
- **代码**：`blindRun/Core/EnvironmentConfig.swift`、`blindRunTests/`、`scripts/hooks/guard.mjs`、`scripts/validate-guard.mjs`、`scripts/` 下的探针脚本。
- **不受影响**：没有证书固定，`Info.plist` 没有 ATS 例外，WebSocket 地址由 scheme 推导。
- **安卓**：`blind-run-android` 同样写死旧 IP，由后端 `#885` 跟踪，不在本仓库范围内。
