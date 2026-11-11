import SwiftUI

// MARK: - 订单页 v7 顶栏（#917，定稿 `docs/ui/mockups/blind-order-tracking-20261109/` 第 1 条）
//
// 返回 / 重复当前状态（喇叭）/「···」更多操作 / 右上角「求助」胶囊。①–④ 压在深色头上（`.onDark`），
// ⑤–⑧ 压在地图上（`.onMap`，#918 用）。**这个组件不判订单状态**：求助走云端还是本地拨号
// 由调用方传进来的 `BlindHomeSOSMode` 决定（判定只在 `BlindHomeSOSMode.resolve` 一处）。
//
// 可点区：看得见的圆钮与胶囊 44pt，可点区 64pt（盲人端下限）—— 边距挂在 label 里，
// 挂在 Button 外面撑不大可点区（记忆 `button-frame-outside-label-does-not-grow-hit-area`）。

/// 顶栏压在什么上面。
enum BlindOrderBarSurface: Equatable {
    /// ①–④ 的深色头。
    case onDark
    /// ⑤–⑧ 的地图（#918）。
    case onMap
}

/// v7 稿里 `AppColors` 没有的几种颜色。**只给订单页 v7 用**（#917 深色头、#918 地图顶栏）。
///
/// 深色头亮暗同值（稿只画了亮色，深色头在暗色下本来就是深的）；白底抽屉与文字仍走 `AppColors.Flow`，跟随系统明暗。
/// 对比度（WCAG 相对亮度）：标题 `#A8C8FF` 压最亮那端 `#353C4F` 约 7.0:1；小字 `#C9CFDB` 约 8.0:1；
/// 求助粉字 `#FF9AA2` 约 5.9:1；粉描边 `#FF8C95` 约 5.3:1（控件边界门槛 3:1）。
enum BlindOrderV7Palette {
    static let headerTop = Color(uiColor: UIColor(rgb: 0x252A38))
    static let headerMiddle = Color(uiColor: UIColor(rgb: 0x2C3243))
    static let headerBottom = Color(uiColor: UIColor(rgb: 0x353C4F))
    static let headerEyebrow = Color(uiColor: UIColor(rgb: 0xC9CFDB))
    static let headerTitle = Color(uiColor: UIColor(rgb: 0xA8C8FF))
    /// 深色头上的圆钮底：12% 白。
    static let roundOnDark = Color.white.opacity(0.12)
    static let helpOnDarkText = Color(uiColor: UIColor(rgb: 0xFF9AA2))
    static let helpOnDarkStroke = Color(uiColor: UIColor(rgb: 0xFF8C95))
    /// 当前步卡片上半截的深色块。
    static let cardDark = Color(uiColor: UIColor(rgb: 0x2E3445))

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [headerTop, headerMiddle, headerBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 「···」里的一项。`kind` 只决定 identifier（守卫 `stale-ui-test-identifier` 只认字面量）。
struct BlindOrderMenuItem: Identifiable {
    enum Kind: String {
        case changeVolunteer
        case cancelBooking
        case shareRunPlan
        case runnerMessage
    }

    let kind: Kind
    let title: String
    var isDestructive = false
    let action: () -> Void

    var id: String { kind.rawValue }
}

/// 顶栏顶上那几个尺寸。
enum BlindOrderTopBarMetrics {
    /// 看得见的圆钮与胶囊高度（稿 44）。
    static let visibleSize: CGFloat = 44
    /// 可点区（盲人端下限）。
    static let hitSize: CGFloat = AppTouchTarget.blindPrimary
}

struct BlindOrderTopBar: View {
    let surface: BlindOrderBarSurface
    let onBack: () -> Void
    let onRepeatStatus: () -> Void
    /// 空 = 不放「···」（① 匹配中没有次要操作）。
    var menu: [BlindOrderMenuItem] = []
    /// 求助中心底部那条走云端还是本地拨号。**只决定胶囊的样子**，点下去一律打开求助与安全中心。
    let sosMode: BlindHomeSOSMode
    let onHelp: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            backButton
            Spacer(minLength: 0)
            repeatButton
            if !menu.isEmpty {
                moreMenu
            }
            BlindOrderHelpPill(surface: surface, isCloud: sosMode == .cloudTrigger, action: onHelp)
        }
        .padding(.horizontal, 8)
        // 整条栏对读屏是一组，顺序就是视觉顺序：返回 → 喇叭 → ··· → 求助。
        .accessibilityElement(children: .contain)
    }

    // MARK: 返回

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                if surface == .onDark {
                    Text("订单").flowFont(FlowV2Fonts.body())
                }
            }
            .foregroundColor(surface == .onDark ? BlindOrderV7Palette.headerTitle : AppColors.Flow.primaryText)
            .padding(.horizontal, surface == .onDark ? 8 : 0)
            .frame(minWidth: BlindOrderTopBarMetrics.visibleSize, minHeight: BlindOrderTopBarMetrics.visibleSize)
            .background {
                if surface == .onMap { roundBackground }
            }
            .padding((BlindOrderTopBarMetrics.hitSize - BlindOrderTopBarMetrics.visibleSize) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回订单列表")
        .accessibilityIdentifier("blindOrderTopBarBackButton")
    }

    // MARK: 重复当前状态

    /// 🔴 盲人端每个关键页面都要有（skill `aidrun-a11y-voice`）。identifier 沿用改版前导航栏那一枚。
    private var repeatButton: some View {
        Button(action: onRepeatStatus) {
            roundLabel(systemImage: "speaker.wave.2.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重复当前状态")
        .accessibilityHint("点击后重新播报当前订单状态")
        .accessibilityIdentifier("blindOrderFlowRepeatStatusButton")
    }

    // MARK: ···

    private var moreMenu: some View {
        Menu {
            ForEach(menu) { item in
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                    Text(item.title)
                }
                .modifier(BlindOrderMenuItemIdentifier(kind: item.kind))
            }
        } label: {
            roundLabel(systemImage: "ellipsis")
        }
        .accessibilityLabel("更多操作")
        .accessibilityHint(menu.map(\.title).joined(separator: "、"))
        .accessibilityIdentifier("blindOrderTopBarMoreMenu")
    }

    private func roundLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(surface == .onDark ? .white : AppColors.Flow.primaryText)
            .frame(width: BlindOrderTopBarMetrics.visibleSize, height: BlindOrderTopBarMetrics.visibleSize)
            .background(roundBackground)
            .padding((BlindOrderTopBarMetrics.hitSize - BlindOrderTopBarMetrics.visibleSize) / 2)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var roundBackground: some View {
        switch surface {
        case .onDark:
            Circle().fill(BlindOrderV7Palette.roundOnDark)
        case .onMap:
            Circle()
                .fill(AppColors.Flow.surface)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
    }
}

// MARK: - 求助胶囊

/// 右上角「求助」。**所有订单页都在同一个位置**（负责人 2026-11-09 第 1 条，推翻 10-06 / 10-07「求助留底部」）。
///
/// 读屏标签与改版前底部那枚相同（`EmergencySafetyCopy.hubAccessibilityLabel`）：功能没变，只是换了位置。
/// identifier 沿用 `blindOrderFlowSafetyHubButton`，守着「求助入口在不在、按不按得到」的 UI 用例不用换判据。
///
/// 样子三种（稿 v7）：深色头上透明底粉描边；地图上白底红字；`isCloud`（只有 `IN_PROGRESS`）红底白字。
struct BlindOrderHelpPill: View {
    let surface: BlindOrderBarSurface
    let isCloud: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "shield")
                    .font(.system(size: 15, weight: .semibold))
                Text("求助")
                    .flowFont(FlowV2Fonts.callout(bold: true))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(ink)
            .padding(.horizontal, 16)
            .frame(minHeight: BlindOrderTopBarMetrics.visibleSize)
            .background(Capsule().fill(fill))
            .overlay {
                if surface == .onDark && !isCloud {
                    Capsule().strokeBorder(BlindOrderV7Palette.helpOnDarkStroke, lineWidth: 1.5)
                }
            }
            .padding(.vertical, (BlindOrderTopBarMetrics.hitSize - BlindOrderTopBarMetrics.visibleSize) / 2)
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(EmergencySafetyCopy.hubAccessibilityLabel)
        .accessibilityHint(EmergencySafetyCopy.hubAccessibilityHint)
        .accessibilityIdentifier("blindOrderFlowSafetyHubButton")
    }

    private var ink: Color {
        if isCloud { return .white }
        return surface == .onDark ? BlindOrderV7Palette.helpOnDarkText : AppColors.Flow.helpText
    }

    private var fill: Color {
        if isCloud { return AppColors.destructive }
        return surface == .onDark ? .clear : AppColors.Flow.surface
    }
}

/// 菜单项 identifier。字面量分支的理由同 `OrderFlowBottomActions.Owner`。
private struct BlindOrderMenuItemIdentifier: ViewModifier {
    let kind: BlindOrderMenuItem.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .changeVolunteer: content.accessibilityIdentifier("blindIntroCallDeclineButton")
        case .cancelBooking: content.accessibilityIdentifier("blindOrderMenuCancelBooking")
        case .shareRunPlan: content.accessibilityIdentifier("blindOrderMenuShareRunPlan")
        case .runnerMessage: content.accessibilityIdentifier("blindOrderFlowRunnerMessageRow")
        }
    }
}
