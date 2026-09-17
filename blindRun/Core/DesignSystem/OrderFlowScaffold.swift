import SwiftUI

// MARK: - 订单页两端共用的外壳

/// 跑者端与陪跑员端订单页**同一个**外壳：可滚动的卡片列 + 贴底的操作区。
///
/// 设计交付文档 v3 §9《组件复用映射》要求两端组件同构 —— 四步进度条只有第 1 步文案不同
/// （「匹配」/「邀请」），底部版位完全一致。所以外壳抽在这里，两端各自只提供**内容**。
///
/// **不抽进来的东西**：跑者端的头像变形（`matchedGeometryEffect`）、倒计时、跑步中那三个数字、
/// 定位新鲜度行。它们在陪跑员端前三态没有对应物 —— 搬进来就是给一个实现造抽象，
/// 而那正好是下一个人读这个文件时最想知道「为什么这里有个只有一处用到的参数」的地方。
///
/// 动效也不在这里：跑者端那条 `.animation(_:value: phase)` 由调用方挂在这个视图上，
/// 效果与挂在内部的 `VStack` 上相同（修饰符向下传播），而 `phase` 是跑者端独有的维度。
struct OrderFlowScaffold<Content: View>: View {
    let bottom: OrderFlowBottomActions
    /// 卡片列。从上到下依次是状态卡、信息卡、以及「刚才那一下的结果」。
    /// 由调用方自己决定哪几块出现 —— 跑起来之后信息卡整块不渲染，那是内容而不是骨架的事。
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableContentColumn()
            }
            bottom
        }
        .background(AppColors.Flow.page)
    }
}

// MARK: - 底部操作区

/// 主按钮（可能为空）+ 可选的「求助与安全」。
///
/// 设计意图：旧版把打电话、修改取消、求助三个按钮并排，重点不清。这里最多两个版位，
/// 且第二个的文案与位置**永不变化** —— 视障用户靠位置记忆操作。
///
/// 两个能力是为设计交付文档 v3 加的，**跑者端同样用得上**：
///
/// - `caption`：按钮**上方**那行小字（汇合态「见面并握好引导绳后再按」）；
/// - `safetyHub == nil`：整枚「求助与安全」不出现（陪跑员端的邀请态、跑者已取消态）。
struct OrderFlowBottomActions: View {
    /// 哪一端在用这条底栏。**只决定两枚按钮的 `accessibilityIdentifier`。**
    ///
    /// 🔴 **为什么不是一个 `identifier: String` 参数**（那样写更短，而且是我的第一版）：
    /// `scripts/hooks/guard.mjs` 的 `stale-ui-test-identifier` 只认**字面量调用形式**
    /// `accessibilityIdentifier("x")`（正则 `accessibilityIdentifier\(\s*"`）。
    /// 把 id 变成参数之后，App 侧那份 identifier 清单里就再也没有这两个 id ——
    /// 守卫会把 UI 测试里对它们的引用全判成「App 侧不存在」，而**运行时其实是好的**。
    /// 也就是说：改成参数不会弄坏 App，会弄瞎那道唯一能发现 UI 测试漂移的检查
    /// （本仓库 CI 跑不了 XCTest，红用例照样能合进 main）。
    ///
    /// 所以这里按 owner 分支、两边各写一个字面量。多三行，换守卫继续看得见。
    enum Owner {
        case blindRunner
        case volunteer
    }

    let owner: Owner
    let primary: OrderFlowPrimaryAction?
    /// `nil` = 这一屏不提供求助与安全。
    let safetyHub: OrderFlowSafetyHubAction?

    var body: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            if let primary {
                if let caption = primary.caption {
                    // 🔴 **对读屏隐藏，同一句话改走主按钮的 hint**（见 `OrderFlowPrimaryAction.caption`）。
                    // 既渲染成独立元素又挂进 hint，VoiceOver 会把它念两遍；
                    // 而只挂 hint 不渲染，不开读屏的低视力用户就完全看不到这句话。
                    Text(caption)
                        .flowFont(FlowFonts.rowDetail())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                tagPrimary(
                    FlowActionButton(
                        primary.title,
                        systemImage: primary.systemImage,
                        style: .primary,
                        isLoading: primary.isLoading,
                        isEnabled: primary.isEnabled,
                        accessibilityHint: primary.resolvedAccessibilityHint,
                        action: primary.action
                    )
                )
            }

            if let safetyHub {
                tagSafetyHub(
                    FlowActionButton(
                        EmergencySafetyCopy.hubTitle,
                        systemImage: "shield",
                        style: .help,
                        accessibilityLabel: EmergencySafetyCopy.hubAccessibilityLabel,
                        accessibilityHint: EmergencySafetyCopy.hubAccessibilityHint,
                        action: safetyHub.action
                    )
                )
            }
        }
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .readableContentColumn()
        // 恒实色，不用材质。理由与订单页那条旧底栏同源（`docs/05-page-specs.md`）：
        // 这一条压着滚动内容，材质会让正文从按钮底下透上来，成了文字叠文字 ——
        // 而那正好打掉低视力用户唯一的通道，且对比度审计查不出来
        // （它查静态配色，不查两层内容叠在一起）。
        .background(AppColors.Flow.surface)
        .overlay(alignment: .top) {
            // 底栏与内容之间唯一的边界。**不调透明度** —— 25% 下只有约 1.4:1，
            // 够不到 WCAG 1.4.11 对控件边界要求的 3:1。
            Rectangle()
                .fill(AppColors.Flow.separator)
                .frame(height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 见 `Owner` 上那段：identifier 必须以字面量调用的形式出现在 App 代码里。
    @ViewBuilder
    private func tagPrimary<V: View>(_ view: V) -> some View {
        switch owner {
        case .blindRunner: view.accessibilityIdentifier("blindOrderFlowPrimaryButton")
        case .volunteer: view.accessibilityIdentifier("volunteerOrderFlowPrimaryButton")
        }
    }

    @ViewBuilder
    private func tagSafetyHub<V: View>(_ view: V) -> some View {
        switch owner {
        case .blindRunner: view.accessibilityIdentifier("blindOrderFlowSafetyHubButton")
        case .volunteer: view.accessibilityIdentifier("volunteerOrderFlowSafetyHubButton")
        }
    }
}

/// 底部那枚黄按钮的全部参数。
struct OrderFlowPrimaryAction {
    let title: String
    var systemImage: String?
    var isLoading = false
    /// `false` ⇒ 走 `.disabled()`，读屏念「变暗」。见 `FlowActionButton.isEnabled` 上那段。
    var isEnabled = true
    /// 按钮**上方**那行小字。
    ///
    /// 它同时进 `accessibilityHint` —— 这句话讲的是「按下去之前要先做什么」，
    /// 属于按钮而不是屏幕，做成独立的读屏元素会让它出现在遍历顺序里的一个前后都没关系的位置。
    var caption: String?
    /// 额外的提示。与 `caption` 同时存在时拼在它后面。
    var accessibilityHint: String?
    let action: () -> Void

    /// `nil` 时 `FlowActionButton` 不挂修饰符 —— 传空串会**覆盖**自动合成的提示
    /// （`accessibilityHintIfPresent` 上有同一条说明）。
    var resolvedAccessibilityHint: String? {
        let parts = [caption, accessibilityHint].compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: "。")
    }
}

/// 「求助与安全」那一枚。文案与图标固定，只有落点由调用方给。
struct OrderFlowSafetyHubAction {
    let action: () -> Void
}
