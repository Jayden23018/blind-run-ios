# 对标大厂 iOS 设计的 GitHub 仓库 / skill，与列表行操作的官方做法（2026-10-30）

**问题**：负责人听说 GitHub 上有教 iOS App 对标大厂设计的项目，能不能借鉴？紧急联系人这种「每行几个操作」，成熟 App 怎么放？

**一句话结论**：**没有找到通过拆解真实大厂 App 来教 iOS 设计的 GitHub 仓库**。负责人听说的最可能是 `awesome-design-md` 或 `ui-ux-pro-max`，两个都已判过不能直接用。这轮只新增一个值得用的：`hig-doctor`（按 HIG 扫 SwiftUI 源码）。列表行操作有明确的官方做法：行里只放内容，点进详情页再操作。

核实日期：2026-10-30。星数来自 `gh api repos/<仓库>`，未采用聚合站的数字。

---

## 1. 候选仓库

| 仓库 | 星数 / 最近 push | 是什么 | 判断 |
|---|---|---|---|
| `nextlevelbuilder/ui-ux-pro-max-skill` | 142,803 / 2026-10-26 | 多平台 UI/UX 设计 skill | 已判过（`design-direction.md` §2）：整体标准低于本仓库（44pt），只取两条对比度规则 |
| `VoltAgent/awesome-design-md` | 122,684（10-21 取）| 84 份品牌**网站**的 DESIGN.md，含 Apple、Uber | 已判过（`awesome-design-md-20261021.md`）：单位 px，分析的是网站，不能抄。**名字最接近「对标大厂」，负责人听说的大概率是它** |
| `wshobson/agents` 的 `mobile-ios-design` | 41,997 / 2026-10-26 | HIG 概述 + SwiftUI 示例 | 不用。示例卡片是 `.foregroundStyle(.blue)` + 阴影，正是本仓库反指纹清单点名的默认值；`Tab(...)` 写法要 iOS 18，本仓库 iOS 16 |
| `Dimillian/Skills` | 4,018 / 2026-03-29 | 作者个人 Codex skills | 不用。偏工程，半年没更新 |
| `AvdLee/SwiftUI-Agent-Skill` | 3,793 / 2026-10-06 | SwiftUI 写法最佳实践 | 不用。讲代码质量不讲审美，与已装的 `swiftui-pro` 重叠 |
| `Prisma-Labs-Dev/apple-skills`（原 `vabole/apple-skills`） | 350 / 2026-09-26 | Apple 文档参考 + `hig` skill | 只可当 HIG 查询用。⚠️ 搜索结果推荐的 `ios-ui-craft` **已被维护者自己停用**，README 给的理由是「Aesthetic manifesto」 |
| `raintree-technology/hig-doctor` | 148 / 2026-10-29 | 按 HIG 静态扫源码，431 条规则，SwiftUI 70 条 | **唯一新增的候选**。输出带严重度和依据，支持只拦新增问题。规则是否与本仓库 64pt、永不封顶字号冲突**没验**，要先试跑 |
| `ebuntario/apple-hig` | 5 / 2026-04-21 | HIG skill | 不用，使用量太小 |
| `dkhamsing/open-source-ios-apps` | 52,905 | 开源 iOS App 清单 | 可当代码样本，但里面不是大厂 App，不能当设计标杆 |

**没查到**：用真实大厂 App 截图逐屏拆解设计的 GitHub 仓库。这类内容通常在商业产品里（如 Mobbin），本轮没有核实。

## 2. 列表行操作：官方怎么说

| 规则 | 来源 |
|---|---|
| 行内文字要短；内容多时「list item titles only, letting people choose an item to reveal its content in a detail view」 | [HIG · Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) |
| 进入下一层用 disclosure indicator（行尾小箭头） | 同上 |
| 破坏性操作要有确认，且确认控件与删除控件分开放 | [WWDC20 · Design with iOS pickers, menus and actions](https://developer.apple.com/videos/play/wwdc2020/10205/) |
| 次要操作（含破坏性操作）可以收进「更多」 | 同上 |
| 同一屏有多个「删除」时，label 要说清删的是谁 | [VoiceOver 评估标准](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/) |
| 主按钮不给破坏性动作 | [HIG · Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)（转引自 `copy-tone-benchmark-20261028.md` §1.3） |
| 滑动操作要开发者自己提供删除项；破坏性按钮用 `role: .destructive`，别只染红 | [SwiftUI swipeActions](https://developer.apple.com/tutorials/data/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:).md)、[Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-custom-swipe-action-buttons-to-a-list-row) |

Uber 把紧急联系人放在 Safety Hub（设置类页面），行程中的安全入口是一枚盾牌图标，不是常驻红条（[Uber 官方](https://www.uber.com/en-AU/ride/safety/)）。

## 3. 对本项目的结论

1. 不装新的设计 skill。审美方向以 `docs/ui/design-direction.md` 为准，外部 skill 的标准多数低于本仓库（记忆 `external-skill-may-lower-your-standard`）。
2. 紧急联系人行改成「行 + 小箭头 → 编辑页，删除放编辑页底部」。本仓库已有先例：PR #481 把空闲时间页的删除挪进编辑页。
3. `hig-doctor` 可以试跑一次当外部检验，要负责人同意安装第三方包。

## 4. 没核实的

- Apple 通讯录、医疗急救卡的实际界面：本轮没有一手截图，上面只引规范。
- `hig-doctor` 没有实际运行。
- 滴滴、微信、支付宝的按钮规范：#558 的调研已查过，没有公开原文。
