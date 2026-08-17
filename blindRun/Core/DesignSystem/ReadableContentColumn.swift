import SwiftUI

/// 页面在**宽窗口**（iPad、iPhone 横屏、iPad 分屏）与**矮窗口**（iPhone 横屏）下的两条布局规则。
///
/// 这两条此前只在 `BlindRunnerHomeView` 里以字面量存在（2026-08-12 那轮只修了首页），
/// 下单页与订单状态页连一条都没有。抽出来的理由不是「以后可能复用」，是**现在就有三个调用点**，
/// 而且规则本身带着一段不能丢的理由 —— 散在三个文件里的 `700` 下次只会被改剩一个。
///
/// 2026-08-16 起也用于登录页与志愿者端的正文页。第一版把适用面写成「盲人端」是记录当时的
/// 调用点，不是一条限制：`iPad Pro (2)` 是发布验证的两台设备之一，而志愿者端在它上面
/// 一条自适应规则都没有（`horizontalSizeClass` / `ViewThatFits` 全 0 命中）。
/// 志愿者是明眼人，但一行正文横跨 1024pt 对谁都不好读。
enum BlindLayout {
    /// 正文列最大宽度。
    ///
    /// 不限宽的话一行正文在 iPad Pro 上会铺满 1024pt，在 iPad Air 上 820pt —— 对**低视力用户**
    /// 尤其糟：把字调大之后仍要横扫整行，换行时极易串行（读到行尾找不回下一行的行首）。
    /// 排版通行的舒适区是每行 45–75 字符，700pt 在放大字号下大致落在这个区间。
    /// iPhone 竖屏（最宽 430pt）比这窄，不受影响。
    static let readableContentWidth: CGFloat = 700

    /// 装饰性地图在矮窗口里的高度上限。
    ///
    /// iPhone 横屏可用高度约 390pt。下单页的辅助地图写死 160pt（41%）、订单状态页的同行地图
    /// 写死 180pt（46%）—— 两张都是 `allowsHitTesting(false)` / `accessibilityHidden` 的纯装饰层，
    /// 信息在旁边的文字里全都有。让不可交互的装饰吃掉近一半横屏高度，和首页地图 300pt 那次
    /// 是同一个本末倒置，只是没人往这两页横过来看。
    ///
    /// 96pt 与首页让位高度的横屏值同源（`BlindRunnerHomeView.mapRevealHeight`）：
    /// 仍能看出「这里有张地图、蓝点在哪」，但不再挤走下面的操作。
    static let compactDecorativeMapHeight: CGFloat = 96

    /// 装饰性地图该多高。
    ///
    /// 抽成纯函数而不是写在 `ViewModifier` 里，是为了让这条分支有一个跑得动的检查 ——
    /// 布局本身只有真机 UI 审计能验，但「矮窗口要压、且压不过原高度」这条规则是纯算术，
    /// 不该也要开一次真机才知道对不对。见 `BlindLayoutTests`。
    ///
    /// `min` 不是多余的：调用方传进来的 `regular` 若本就比 96 矮（未来某张小地图），
    /// 压扁不该反过来把它撑高。
    static func decorativeMapHeight(regular: CGFloat, isCompactHeight: Bool) -> CGFloat {
        isCompactHeight ? min(compactDecorativeMapHeight, regular) : regular
    }
}

extension View {
    /// 把正文限进可读列宽并居中，背景仍铺满。
    ///
    /// 两层 `frame` 缺一不可：第一层收宽度，第二层把这条窄列在父容器里居中 ——
    /// 只写第一层的话内容会靠左贴边，iPad 上右边空出一大片。
    func readableContentColumn() -> some View {
        frame(maxWidth: BlindLayout.readableContentWidth)
            .frame(maxWidth: .infinity)
    }

    /// 装饰性地图的高度：竖屏用 `regular`，矮窗口压到 `BlindLayout.compactDecorativeMapHeight`。
    ///
    /// 只在 `verticalSizeClass == .compact` 时压 —— iPad 横屏是 `.regular`，那里高度充裕，
    /// 压扁反而让地图小到看不出东西。
    func decorativeMapHeight(_ regular: CGFloat) -> some View {
        modifier(DecorativeMapHeight(regularHeight: regular))
    }
}

private struct DecorativeMapHeight: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let regularHeight: CGFloat

    func body(content: Content) -> some View {
        content.frame(
            height: BlindLayout.decorativeMapHeight(
                regular: regularHeight,
                isCompactHeight: verticalSizeClass == .compact
            )
        )
    }
}
