@AGENTS.md

This is the AidRun native iOS frontend repository only.

The backend is external. All real HTTP requests use `https://47.114.113.171`; do not add server implementation code or another real-server address to this repository.

## 硬约束（违反会被 CI 拦或造成线上缺陷）

- **接口契约的唯一源在后端仓库** `blind-run-backend` 的 `docs/api_spec.yaml`。本仓库里同名文件已归档为 `_archive-*.bak`，**不要**在这里改契约、也不要照着 `_archive` 写代码。契约要改 → 去后端仓库改；需要后端拍板的开后端仓库 issue（标签 `待后端确认` + `handoff`；`docs/handoff.md` 已冻结）。
  - `.github/workflows/verify.yml` 的 `specs` job 会校验本仓库调用的每个 `/api/` 路径都在后端 spec 里存在，同时对撞错误码枚举与语音黄金语料。本地先跑一遍（或装一次 `scripts/install-git-hooks.sh`，push 前自动跑）：
    ```bash
    spec="$(mktemp)" && git -C /Users/mac/Downloads/demo show origin/main:docs/api_spec.yaml > "$spec"
    node scripts/validate-spec-coverage.mjs "$spec"
    ```
- **并发模型只用一种**。同一条数据流里不要既订阅 Combine publisher 又 `await` async 函数；view model 不要同时持有 `AnyCancellable` 和 `Task`。混用是这类项目最常见的架构漂移，且会制造只在真机上偶现的时序 bug。新代码一律 async/await。
- **枚举解码遇未知值不许整条崩**。后端往枚举加值而 spec 没跟上时（后端有 `SpecDriftTest.enumsMatchCode` 拦，但不是万无一失），客户端要能降级到「未知」而不是整页空白 —— 对盲人端「点了没反应」就是事故。见 commit `4793805`。
- **团队号**：命令行真机跑测前先调 skill `aidrun-device-test` 判定用哪个签名团队，**这里和任何文档都不写具体团队号** —— 它随人、随机器变，2026-10-15 三个并行会话照抄文档里的号全部签名失败（#441）。工程里的默认值只当「当前值」去 `project.pbxproj` / `scripts/device-test.sh` 当场查，别背。
  工程团队是**个人类型**账号时，加进来的成员（含 Admin）拿不到开发权限，只换 team 签不动，要用自己的免费个人团队并连 bundle id 前缀一起换（做法与依据见该 skill 第二节）。CI 上走 `CODE_SIGNING_ALLOWED=NO`，不需要 team id。
  守卫 `hardcoded-team-id` 会拦「在 `.md` 里写 `DEVELOPMENT_TEAM=<10 位团队号>`」。
- **UI 测试断言前先滚动**：SwiftUI `List` 不渲染屏幕外的行，直接断言会假失败（见 commit `4cee939`）。
- **CI 跑不了任何 XCTest**：高德 SDK 没有 arm64-sim slice，模拟器通道永久不可用，而 runner 只有模拟器。CI 做的是 `build-for-testing` 编译门禁 + 规格校验；单测与 UI 测试**一律真机本地跑**，用 `scripts/device-test.sh`（会先探活、锁屏立即失败、按小写 `Test case` 统计）。
