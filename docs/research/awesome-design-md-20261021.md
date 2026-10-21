# awesome-design-md 与 DESIGN.md 格式：本项目能借鉴什么（2026-10-21）

**问题**：GitHub 上的 `awesome-design-md` 有没有能直接抄、或可以借鉴的东西？

**一句话结论**：**里面的 84 份文件一份都不能直接抄**——它们分析的是品牌**网站**，单位是 px、断点是浏览器宽度、触达区 44px，
和本项目的 iOS 原生、Dynamic Type、64pt、深色模式全部对不上。**能借鉴的只有格式**（「精确 token + 为什么」+ Do/Don't + Known Gaps），
以及 Google 官方 CLI 的对比度 lint。我们的 `docs/ui/design-direction.md` 已经覆盖了格式的大部分，缺的只是一份机器可读的 token 块。

核实日期：2026-10-21。

---

## 1. 它是什么

| 项 | 事实 | 来源 |
|---|---|---|
| 仓库 | `VoltAgent/awesome-design-md`，MIT，2026-03-31 建，最近 push 2026-10-14 | GitHub API |
| 热度 | 122,684 stars / 13,622 forks（2026-10-21 GitHub API 实取） | GitHub API |
| 内容 | `design-md/` 下 84 个目录，每个是从一个品牌网站扒出的 `DESIGN.md`（Stripe、Linear、Vercel、Apple、Notion、Claude、Uber 等） | GitHub contents API |
| 现状 | 部分目录的 `README.md` 已写「Design system details have been moved to: https://getdesign.md/…」，在往商业站 getdesign.md 导流；`DESIGN.md` 本体仍在仓库里（apple 那份 562 行） | 仓库原文 |
| 格式来源 | Google Stitch 提出的 DESIGN.md；正式规范在 `google-labs-code/design.md`（Apache-2.0，`version: alpha`），CLI 是 npm `@google/design.md`，当前 0.4.0 | 官方 README、`docs/spec.md`、`npm view` |

DESIGN.md 格式 = 文件头 YAML token（`colors` / `typography` / `rounded` / `spacing` / `components`）+ 固定顺序的 `##` 正文
（Overview → Colors → Typography → Layout → Elevation & Depth → Shapes → Components → Do's and Don'ts）。
token 给精确值，正文讲为什么、怎么用。

## 2. 为什么不能直接抄

拿最接近我们的 `design-md/apple/DESIGN.md` 逐项对：

| 它写的 | 本项目 | 冲突在哪 |
|---|---|---|
| 分析对象是 apple.com 营销页（「photography-first … museum gallery」） | iOS 原生 App | 不是 iOS HIG，是网页设计 |
| 字号固定 px：hero 56px、body 17px，断点 ≤419px … ≥1441px 逐档缩字 | 字号走 Dynamic Type，**永不封顶**（design-direction §3） | 规范的 Dimension 只认 `px` / `em` / `rem`，没有 pt，也没有文本样式概念 |
| Touch Targets「Minimum 44 × 44px」，导航链接「~32 × 80px」 | `PrimaryButton` `minHeight: 64` | 抄过来是降标准（记忆 `external-skill-may-lower-your-standard`） |
| 只记录浅色版（Known Gaps 自己承认深色没覆盖）；规范本身没有深色模式字段 | `AppColors.swift` 有 29 处、`FlowPalette.swift` 有 63 处 dark 相关定义 | 格式装不下我们的动态色 |
| hover、`backdrop-filter`、`srcset`、汉堡菜单 | SwiftUI | 网页专属（记忆 `web-design-advice-is-mostly-not-for-swiftui`） |
| 品牌调性：高饱和品牌色、照片优先 | 盲人端「市政窗口式克制」，装饰色要过对比度（design-direction §1、§2） | 方向相反 |

另外，照着某个真实品牌的视觉做，本身就有仿冒风险，不适合上架应用。

## 3. 能借鉴的

1. **「Known Gaps」节**：每份文件末尾写明「这份没覆盖什么」（例如 apple 那份写了表单错误态、深色版没分析到）。
   `design-direction.md` 有「不抄什么」，但没有「本文件没管到什么」。加一节成本很低，能防止模型把没写的地方当成「随便」。
2. **一份机器可读的 token 块**：把 `AppColors` / `AppFonts` / `AppSpacing` 的值导出成 DESIGN.md 的 YAML 头，
   在 claude.ai / Claude Design 出设计稿时当附件喂进去，减少设计稿与实现的色值漂移（2026-09-30 调研的痛点）。
   ⚠️ 前提是**从 Swift 源码生成并在 CI 里校验同步**，手写一份就是又一个会漂的副本。
3. **官方 CLI 的 `contrast-ratio` lint**：对 `components` 里每组 `backgroundColor` / `textColor` 算 WCAG AA 4.5:1。
   价值有限：我们已有真机无障碍审计（`AccessibilityAuditTests`）量实际渲染结果，比静态 token 更接近真相；
   而且 lint 只认单一色值，判不了深色模式那一半。只在第 2 条做了之后顺带有用。
4. 格式里的 Do's and Don'ts 节：我们已有（design-direction §7 反指纹清单），不用改。

## 4. 没核实 / 没做的

- 没实际跑 `npx @google/design.md lint`（本机代理会让 `npx -y` 装一半，见全局规则；本次只读了 README 与 spec）。
- 没核实 Claude Design 对 DESIGN.md 有没有专门支持；第 3.2 条只当普通 Markdown 附件用。
- 只逐行读了 apple 一份；其余 83 份只看了目录名。结论「都是网站」来自仓库自述「extracted from real websites」与目录名。

## 来源

- https://github.com/VoltAgent/awesome-design-md （README、`design-md/apple/DESIGN.md`、GitHub API 元数据）
- https://github.com/google-labs-code/design.md （README、`docs/spec.md`）
- https://www.npmjs.com/package/@google/design.md （`npm view` 版本 0.4.0）
- https://stitch.withgoogle.com/docs/design-md/overview/ （仓库 README 引用的格式出处，未单独打开）
