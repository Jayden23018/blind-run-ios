@AGENTS.md

## 硬约束（只放 `AGENTS.md` 与 skill 里没有的三条；其余别在这里补第二份）

- **并发模型只用一种**。同一条数据流里不要既订阅 Combine publisher 又 `await` async 函数；view model 不要同时持有 `AnyCancellable` 和 `Task`。混用是这类项目最常见的架构漂移，且会制造只在真机上偶现的时序 bug。新代码一律 async/await。
- **枚举解码遇未知值不许整条崩**。后端往枚举加值而 spec 没跟上时（后端有 `SpecDriftTest.enumsMatchCode` 拦，但不是万无一失），客户端要能降级到「未知」而不是整页空白 —— 对盲人端「点了没反应」就是事故。见 commit `4793805`。
- **UI 测试断言前先滚动**：SwiftUI `List` 不渲染屏幕外的行，直接断言会假失败（见 commit `4cee939`）。

> 仓库边界与真实服务端地址 → `AGENTS.md` 开头 + §3；契约唯一源与 `_archive-*.bak` 禁读 → §2 / §7；
> `DEVELOPMENT_TEAM` 与冻结文件 → §9；**全部验证命令**（含 `validate-spec-coverage.mjs`、
> `install-git-hooks.sh` 的 pre-push 钩子）以及「CI 跑不了任何 XCTest、单测与 UI 测试一律真机本地跑」
> → skill `aidrun-ship-check`。
>
> 后端仓库两种指代都对且指同一个：GitHub 上叫 `blind-run-backend`，本机 clone 在 `/Users/mac/Downloads/demo`。
>
> 2026-08-08 去重：上面四处此前在本文件各存第二份。§11 那轮把验证命令合进 skill 时漏了本文件，
> 于是 `validate-spec-coverage.mjs` 从「两份」变成了「换个文件的两份」。**别再在这里补第二份。**
