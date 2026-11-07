# 前端全仓审查：从哪些角度查、用什么工具、有没有现成 skill（2026-11-07）

问题：负责人要对整个 iOS 前端做一次审查，目标三个：① 找可以复用的地方 ② 精简、优化 ③ 找旧界面没删干净的残留。
负责人提议用 `improve-codebase-architecture`。本调研回答：外面怎么做这类审查、有哪些工具、哪个 skill 能直接用。

## 一句话结论

**单靠一个 skill 不够，要三条线各配工具**：死代码用 Periphery（编译器索引，不靠 grep 猜），
重复用 jscpd（逐 token 比对），架构深化用 `improve-codebase-architecture` 的流程；
审查框架照 `jazzychad/ios-code-audit` 的「三路并行 + 逐条带 `文件:行号` + 高危项开文件复核」，
但不装它，因为它依赖的 SwiftUI skill 本仓库已有同类（`swiftui-pro`），且它默认把报告写进仓库根目录。

## 1. 现成 skill

| skill | 管什么 | 能不能直接用 | 来源 |
|---|---|---|---|
| `improve-codebase-architecture`（mattpocock 1.3.2） | 找「浅模块」（接口几乎和实现一样复杂），提议合并成深模块；先看 git 历史找常改处，出 HTML 报告，再逐条深挖 | 本机插件缓存里有，但 `disable-model-invocation: true`：**只能负责人手动调起**，模型调不了。**不找死代码** | 本机 `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.3.2/skills/engineering/improve-codebase-architecture/SKILL.md` |
| `jazzychad/ios-code-audit` | 只读审查，出 `CODE_AUDIT.md`：并发、API 新旧、bug、安全、性能、SwiftUI、死代码 / 重复 / 大文件 | 方法可借，不必安装。三路子代理的分工、每条发现的统一格式（位置 / 现象 / 影响 / 建议 / 严重度）、「Critical 先开文件复核」都能照抄 | [GitHub README](https://github.com/jazzychad/ios-code-audit)、[agent-prompts.md](https://raw.githubusercontent.com/jazzychad/ios-code-audit/main/references/agent-prompts.md)（原文已读） |
| 通用死代码 skill（`ln-626-dead-code-auditor` 等） | 未用 import、未调用函数、注释掉的代码块 | 不针对 Swift，靠 grep，误报多，不用 | [claudemarketplaces](https://claudemarketplaces.com/skills/levnikolaevich/claude-code-skills/ln-626-dead-code-auditor)（只看了列表页） |

## 2. 工具

### Periphery（死代码）

- 原理：先编译出 Xcode 的索引库，从入口往下走引用图，走不到的声明就报未使用。能报未用的类型、函数、参数、枚举值、只写不读的属性、多余的协议（README 原文）。
- **已转商业**：GitHub 仓库归档，作者说小项目和开源项目免费，现在是不限规模的免费公开测试（periphery.pro 原文）。本仓库是公开仓库，属开源项目。
- Homebrew 里还有开源版 3.8.0（MIT），标了「上游已归档，2027-08-12 停用」（本机 `brew info periphery` 实测）。
- 本仓库的坑：
  - 只认编译过的文件。只在没编译的 target 里被引用的代码会被误报 ⇒ 扫描要同时带 App 和两个测试 target。
  - 带原始值的枚举（`String` 枚举）默认算有用，这对本仓库是好事（后端枚举不会被误删）。
  - 高德 SDK 没有模拟器片，不能让 Periphery 自己编译 ⇒ 用 `--skip-build --index-store-path` 读真机编译留下的索引库。本机已有：`DerivedData/blindRun-haoietutwsxrqagabsppzczjuszu/Index.noindex/DataStore`（62M，11-07 22:27）。
  - 只在 `#Preview` 里被引用的视图，旧 issue（#524）说不报警，状态没核实。

### jscpd（重复代码）

- README 列了 Swift。Homebrew 有 5.4.2（本机 `brew info` 实测）。PMD CPD 的 Swift 模块已标废弃，不用。
- 只报「长得一样」的代码段，不判该不该合并；合并与否要人看。

### SwiftLint analyze（备选）

- `unused_declaration` / `unused_import` 两条分析规则，要先存一份全量编译日志再跑。社区报告有误删 `@_exported` import 的问题。Periphery 覆盖它，只在 Periphery 不能用时再考虑。本机已装 swiftlint。

### FengNiao（未用图片资源）

- onevcat/FengNiao：扫 `.xcassets` 里没被代码引用的图片。支持 `--list-only` 只列不删。旧界面删掉后图片常常留着，这条线 Periphery 管不到。

## 3. 审查角度（外面通行 + 本仓库要加的）

通行的（`ios-code-audit` 的 B 组）：`#if false` 与注释掉的代码、跨文件重复的小工具函数、>500 行的大文件、TODO/FIXME、名字带 `Old`/`Legacy`/`V2` 的文件、`#if DEBUG` 外的 `print`、散落的魔法数。

本仓库要另加的：

1. **从入口查页面可达性**：从 App 入口顺着 `NavigationLink` / `sheet` / `fullScreenCover` / tab 列出所有能到的页面，再和全部 `View` 类型对比。Periphery 只能说「没人引用」，说不了「有人引用，但引用它的那页本身已到不了」。
2. **Mock 与 Preview 专用代码**分开统计，不当死代码删（AGENTS §3：Mock 是测试设施）。
3. **安全红线代码只报不改**：SOS、订单状态机、通话磨合、掩码号码相关的文件。
4. **在途的删除先排除**：PR #816（旧约跑表单）、#714–#723 大文件拆分。

## 4. 怎么判结果对不对

- Periphery 前后两次扫描，未使用声明的条数下降，且删掉的每个符号全仓库搜不到引用。
- `build-for-testing` 编译通过（CI 编译门禁）。
- 删掉的页面由负责人在真机上点一遍确认（11-05 起不跑真机测试）。

## 被否的

- 安装 `ios-code-audit`：它依赖的 `swiftui-expert-skill` 与本仓库的 `swiftui-pro` 重复；它默认把 `CODE_AUDIT.md` 写到仓库根，而本仓库的审查报告只落 `docs/review/`。
- PMD CPD：Swift 模块已废弃。
- 通用 grep 型死代码 skill：Swift 的扩展、协议、SwiftUI 修饰符让 grep 误报很多。

## 来源

- https://raw.githubusercontent.com/peripheryapp/periphery/master/README.md （原文）
- https://periphery.pro/a-new-chapter （原文）
- https://github.com/jazzychad/ios-code-audit （原文）
- https://github.com/onevcat/FengNiao （搜索摘要）
- https://github.com/kucherenko/jscpd （搜索摘要，经第三方镜像）
- 本机：`brew info periphery` / `brew info jscpd`（2026-11-07 实测）
