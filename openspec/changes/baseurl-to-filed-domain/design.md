## Context

动机见 `proposal.md`。发布包只有一个真实地址入口 `blindRun/Core/EnvironmentConfig.swift` 的 `DemoCloud.baseURL`，WebSocket 地址由它的 scheme 推导。

2026-10-31 的后端状态：生产正从 `47.114.113.171` 搬到公司服务器 `120.25.214.8`，域名已解析到新机，但 80、443 还不通。所以本变更先把代码改完，真机验证和合并都排在后端部署之后。

## Goals / Non-Goals

**Goals:**

- 发布包只连备案域名。
- 守卫能拦住写回旧 IP，也能拦住看起来像新域名的地址。

**Non-Goals:**

- 不关旧 IP 入口。旧构建还在连它，由后端按 `Jayden23018/blind-run-backend#885` 处理。
- 不做地址回退或多地址切换。
- 不改安卓端。

## Decisions

### 只改一个地址，不加旧 IP 回退

App 里不保留「域名连不上就试旧 IP」的逻辑。备案要求 App 连接填报的域名，回退会让发布包继续带着旧 IP，也违反「地址在 App 内不可配置」。代价是域名出故障时没有自动兜底，用「合并前先确认健康检查和 `wss`」来控制。

### 守卫改成主机全等比较

旧判据是 `u.includes(REAL_HOST)`。换成域名后，`https://blindrun.culiu-tech.com.evil.net` 和 `https://staging-blindrun.culiu-tech.com` 都会被当成真实主机放行。改成拿 URL 的主机部分和 `REAL_HOST` 全等比较，带端口的写法也按「别的主机」拦下。

### 守卫单独认旧 IP 的裸字符串

`server-addr` 的正则要求有 scheme，`"47.114.113.171"` 这种裸字符串拼 `URLComponents` 的写法能穿过去。旧 IP 单列 `RETIRED_HOST`，只要出现在非注释行就拦。纯注释行继续放行，因为这条规则的目标是出货代码。

### 夹具的抓取来源保留

`blindRunTests/Fixtures/_manifest.json` 记录夹具当时从哪里抓的，是历史事实，也不进发布包。保留原值。`docs/research/`、`docs/review/`、已归档的 OpenSpec 变更和带日期的报告同样是历史记录，不改。

### 生成代码不手改

`Packages/AidRunAPI` 的生成文件要和后端契约一致，pre-push 会比对。手改旧地址会让比对变红，所以等后端 `OpenApiConfig.java` 的 server 合进 `main` 后，用 `scripts/sync-api-client.sh` 重新生成。

## Risks / Trade-offs

- [后端没部署就合并] → 新构建全部连不上服务器。PR 保持草稿，合并前复测 `/actuator/health` 和 `wss`。
- [域名解析或证书故障] → 全站请求失败，App 里没有回退。合并前核证书校验通过，后端监控改到新地址由 `Jayden23018/blind-run-backend#885` 负责。
- [生成代码里还有旧 IP] → `AidRunAPI` 确实链进了发布包。2026-10-31 实测，Release 二进制里旧 IP 有 1 处，就是生成代码 `Servers` 的字面量。所以「发布包里搜不到旧 IP」要在重新生成之后验收。

## Migration Plan

1. 后端完成 `#885` 部署，域名 `/actuator/health` 返回 200，`wss` 能连上。
2. 后端契约的 server 地址合进 `main`，本仓库重新生成 `Packages/AidRunAPI`。
3. 真机连域名跑登录和 WebSocket 流程，贴 `passed=N failed=0`。
4. 检查发布包里搜不到旧 IP，PR 转正式并合并。

回滚：还原 `DemoCloud.baseURL` 和守卫的 `REAL_HOST`，重新发版。旧入口由后端保留到旧构建退场，所以回滚窗口内旧地址仍可用。

## Open Questions

无。域名和批准已在 #621 确认。
