# iOS Dynamic Type 档位与 WCAG 200% 的关系

**核实日期**：2026-08-12
**调研问题**：`dynamicTypeSize(...accessibility3)` 这样的封顶，够不够 WCAG 1.4.4 要求的「文字放大 200% 不裁切」？
**为什么开这一轮**：`docs/review/blind-app-full-review-20260812.md` 初稿断言「封顶 AX3 违反 WCAG 1.4.4，AX3 约 175%，够不到 200%」。这个数字是**凭印象写的**，落进了一份已发布的报告。动手改代码前核了一次，结论相反。

> 篇幅短是刻意的 —— 这是一次事实核对，不是选型调研。留档的价值在于**下次不用再查**，
> 以及记住这个数字曾经被写错过一次。

---

## 结论

| 档位 | body 字号 | 相对默认（17pt） |
|---|---|---|
| Large（默认） | 17pt | 100% |
| AX1 | 28pt | ~165% |
| AX2 | 33pt | ~194% |
| **AX3** | **40pt** | **~235%** |
| AX4 | 47pt | ~276% |
| AX5 | 53pt | ~312% |

**封顶 AX3 在合规上是过关的** —— 235% 已经越过 WCAG 1.4.4 的 200%。原报告那句「约 175%，够不到 200%」是错的。

检索到的独立佐证：Dynamic Type 在 **AX3 档就超过 200%**，在 **AX5 档 body 超过 300%**；多个来源把 AX5 记作约默认的 **310%**，与 53 ÷ 17 ≈ 3.12 吻合。

## 仍然要去掉封顶的两条理由（换了论据，不是换了结论）

1. **AX4 / AX5 正是低视力用户实际会设的档位。** 本 App 的 `VisionLevel.LOW_VISION` 是数据模型里的一等公民，封在 AX3 等于把最后两级从目标用户手里拿走。合规达标 ≠ 对目标用户够用。
2. **全仓只有 `HighContrastText` 一个组件封顶**，其余文本都不封。于是同一屏里一部分字会长、一部分不会，得到的是**不一致的缩放** —— 比"全封"和"全不封"两个极端都差。

封顶本身是**合法技巧**（检索到的通行建议正是「布局撑不住整个 AX 区间时，封在某个档位，例如 AX2」），代价是把裁切风险转移到布局上。所以去掉封顶必须由真机 `blindRunUITests/AccessibilityAuditTests` 的 `.dynamicType` 审计兜底。

## 两条配套事实

- **文本样式之间缩放速率不同。** Body 比 Title 系列涨得快 —— 在 AX5 档 Body 会**大于** Title 1。所以不能拿一个样式的比例去推另一个。
- **SF Pro 会在 ≤19pt / ≥20pt 之间自动切换 Text 与 Display 字形。** Body 从 AX1（28pt）起就全部落在 Display 区间。

完整逐样式逐档位的字号表以 Apple HIG「Typography」页为准，本表只覆盖 Body。

## 来源

均为 2026-08-12 核实。

- [Apple: Building accessible apps](https://developer.apple.com/accessibility/index.html)
- [App Store Connect — Larger Text evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria/)
- [Get started with Dynamic Type — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10074/)
- [Supporting Dynamic Type and Larger Text（createwithswift）](https://www.createwithswift.com/supporting-dynamic-type-and-larger-text-in-your-app-to-enhance-accessibility/)
- [A product designer's guide to Dynamic Type in iOS](https://medium.com/design-bootcamp/a-product-designers-guide-to-dynamic-type-in-ios-a105dda39a95)
