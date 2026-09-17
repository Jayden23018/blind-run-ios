import UIKit

/// 底部标签栏的外观。**两个角色容器共用这一份**（`BlindRunnerTabView` /
/// `VolunteerTabView`），所以它不属于任何一端，放在设计系统里。
///
/// `UITabBar.appearance()` 是全局的，两处设的是同一份值，而同一时刻只有一个角色在场
/// —— 共用因此是安全的，也是必须的：两份会漂移，而漂移的那半份是 13pt 的对比度。
enum FlowTabBarAppearance {
    /// 标签栏未选中标签的取色。
    ///
    /// **必须走 `UITabBarAppearance`**：SwiftUI 到 iOS 16 只有 `.tint()`（管选中态），
    /// 未选中态没有对应的修饰符。
    ///
    /// 不只是为了对设计稿：**iOS 默认的未选中灰 `#8E8E93` 压白底只有 3.26:1**，
    /// 而标签栏是 13pt 的小字。设计稿的 `#6B7385` 是 4.76:1。取值与理由在
    /// `AppColors.Flow.tabUnselectedTone`。
    static func apply() {
        let appearance = UITabBarAppearance()
        // 🔴 **必须是不透明的实色底，不能用 `configureWithDefaultBackground()`。**
        //
        // 那个给的是**半透明材质**，于是内容滚到标签栏之下时，标签文字的有效背景会被
        // 下面的内容压暗 —— 而首页滚到底下压着的正是深蓝卡 `#15224A`。
        // 未选中标签 `#6B7385` 压白底是 4.76:1，但材质有效不透明度 0.9/0.8/0.7 时分别
        // 只有约 3.71 / 3.02 / 2.40，全部低于亮色正文 4.5:1 的硬线，
        // 而那是全屏最小的 13pt 文字。
        //
        // 连带：`FlowDesignSystemTests.testTabBarLabelsClearTheBodyThresholdOnTheTabBarSurface`
        // 的前提就是「标签栏底与卡片同一个表面色」。用半透明材质的话那条断言算的是一个
        // 真机上不成立的数 —— 绿灯替一个不存在的保证背书。
        //
        // 设计稿本来也是实色：`home.html:14` 的 `.tab{...background:#fff;...}`。
        // 与 `docs/05-page-specs.md` 对订单页底栏那条「背景恒为实色，不用 `.regularMaterial`」
        // 是同一条理由（那次是滚动时正文从按钮底下透上来，2026-09-07 真机报的「穿模」）。
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { traits in
            let tone = AppColors.Flow.surfaceTone
            return UIColor(rgb: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        }

        let unselected = UIColor { traits in
            let tone = AppColors.Flow.tabUnselectedTone
            return UIColor(rgb: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        }
        for item in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            item.normal.iconColor = unselected
            item.normal.titleTextAttributes = [.foregroundColor: unselected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
