## 1. 守卫

- [x] 1.1 `scripts/hooks/guard.mjs`：`REAL_HOST` 换成备案域名，`server-addr` 改成主机全等比较，并拦旧 IP 的裸字符串
- [x] 1.2 `scripts/validate-guard.mjs`：更新地址用例，补旧 IP、裸字符串、长主机、别的子域、带端口的用例，并验红

## 2. App 与测试

- [x] 2.1 `blindRun/Core/EnvironmentConfig.swift`：改 `DemoCloud.baseURL` 和注释
- [x] 2.2 `blindRunTests/blindRunTests.swift`：改两条地址断言，测试名不再写 IP
- [x] 2.3 改 `BlindIdentityVerificationView.swift`、`BlindIdentityVerificationViewModelTests.swift`、`LegalLinksTests.swift` 的注释

## 3. 脚本

- [x] 3.1 `scripts/` 下 6 个探针脚本的默认地址换成 `https://blindrun.culiu-tech.com`
- [x] 3.2 `scripts/validate-spec-coverage.mjs`：改注释和自测里的地址
- [x] 3.3 `Packages/AidRunAPI/Tests/AidRunAPITests/BearerTokenMiddlewareTests.swift`：改测试用的 baseURL

## 4. 文档

- [x] 4.1 `AGENTS.md`、`CLAUDE.md`、`README.md`、`plan.md`
- [x] 4.2 `docs/01`、`docs/02`、`docs/08`、`docs/10`、`docs/technical-design-overview.md`、`docs/ui/ui-review-checklist.md` 里仍在生效的地址

## 5. 本地验证

- [x] 5.1 `node scripts/validate-guard.mjs`、`node scripts/validate-spec-coverage.mjs`、`node scripts/validate-agents-size.mjs` 全过
- [ ] 5.2 工程编译通过

## 6. 等后端部署后做（`Jayden23018/blind-run-backend#885`）

- [ ] 6.1 确认 `https://blindrun.culiu-tech.com/actuator/health` 返回 200，`wss` 能连上，证书校验通过
- [ ] 6.2 后端契约的 server 地址合进 `main` 后，用 `scripts/sync-api-client.sh` 重新生成 `Packages/AidRunAPI`
- [ ] 6.3 真机连域名跑登录和 WebSocket 流程，贴 `passed=N failed=0`
- [ ] 6.4 Release 构建里搜不到旧 IP
- [ ] 6.5 归档本变更，PR 转正式，用 `bash ~/.claude/scripts/ship.sh` 合并
