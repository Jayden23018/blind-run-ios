import CoreGraphics

// MARK: - App Spacing

/// 间距 / 圆角 / 触达尺寸的具名常量。
///
/// **立此文件的理由不是「以后可能复用」，是现在就不一致。** 2026-09-08 实测全仓：
/// `.padding(n)` 157 处用了 **19 种**取值，`spacing: n` 248 处用了 **15 种**，
/// 其中 6 / 10 / 14 / 18 / 2 这些非 4 倍数的散值就是「随手调一下」留下的痕迹。
/// 同屏节奏乱掉说不出哪里丑，但对低视力用户是实打实的可用性问题 ——
/// 字号放大到 AX5 之后，不成比例的间距会让「哪几行是一组」这件事彻底失去线索。
///
/// 反过来 `cornerRadius` 实测只有 **8 / 12 / 16** 三个真实取值（69 处），本来就规整，
/// 所以下面只给三档，不多造。
///
/// ⚠️ **不做一次性重构。** 474 处存量按「新写的用 token、改到的顺手换」推进 ——
/// 一次全换会把 474 处视觉改动混进一个无法审的 diff，而其中一部分（20 / 28pt）
/// 归并到相邻档会真的改变视觉，那是设计决定不是机械替换。
enum AppSpacing {
    /// 网格基数。所有档位都是它的整数倍 —— `AppSpacingTests` 会检查这条。
    static let unit: CGFloat = 4

    /// 4pt。紧邻元素之间（图标与它的标签、两行同属一条信息的文字）。
    static let xSmall: CGFloat = unit
    /// 8pt。一组之内的元素间距。实测最高频的 `spacing` 取值（66 处）。
    static let small: CGFloat = unit * 2
    /// 12pt。次高频（48 处）。卡片内的行距、按钮内的横向留白。
    static let medium: CGFloat = unit * 3
    /// 16pt。分组之间。也是 SwiftUI `.padding()` 的系统默认值。
    static let large: CGFloat = unit * 4
    /// 24pt。区块之间、页面水平边距。实测最高频的 `padding` 取值（36 处）。
    static let xLarge: CGFloat = unit * 6
    /// 32pt。大段留白，主操作区与其余内容的分隔。
    static let xxLarge: CGFloat = unit * 8

    /// 全部档位，由小到大。测试直接读这张表（与 `AppColors.tones` 同一个模式）。
    ///
    /// ⚠️ 新增档位时**必须同时加进这张表**，否则 `AppSpacingTests` 检查不到它 ——
    /// 而那正是这套 token 唯一的守卫。
    static let all: [(name: String, value: CGFloat)] = [
        ("xSmall", xSmall),
        ("small", small),
        ("medium", medium),
        ("large", large),
        ("xLarge", xLarge),
        ("xxLarge", xxLarge),
    ]
}

/// 圆角。实测只有三个真实取值，照实测给，不多造档。
enum AppCornerRadius {
    /// 8pt。小卡片、输入框、次级容器（实测 37 处）。
    static let small: CGFloat = 8
    /// 12pt。主按钮与主要卡片（实测 21 处）。
    static let medium: CGFloat = 12
    /// 16pt。大面积容器（实测 10 处）。
    static let large: CGFloat = 16

    /// 全部档位，由小到大。理由同 `AppSpacing.all`。
    static let all: [(name: String, value: CGFloat)] = [
        ("small", small),
        ("medium", medium),
        ("large", large),
    ]
}

/// 触达尺寸。**这两个数是规范约束，不是审美选择** —— 改小了是无障碍事故。
///
/// 实测 `64` 散落在 **44 处**、`44` 在 8 处，全是字面量。抽出来的价值不在少打几个字，
/// 在于 `AppSpacingTests` 能钉住下限：字面量散在 44 个地方时，没有任何东西拦得住
/// 有人为了「排版好看一点」把某一处调成 56。
enum AppTouchTarget {
    /// 盲人端主操作按钮最小高度。`AGENTS.md` §8 与 `docs/ui/ui-review-checklist.md` 都钉着这个数。
    /// 比 HIG 的 44 大一截，因为盲人用户是靠**摸索**命中而不是靠看准。
    static let blindPrimary: CGFloat = 64

    /// Apple HIG 的通用最小触达尺寸。任何可点元素都不得低于它。
    static let minimum: CGFloat = 44
}
