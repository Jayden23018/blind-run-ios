import SwiftUI

// MARK: - 陪跑员订单页 v7 顶栏（#945，定稿 `docs/ui/mockups/volunteer-order-v7-20261111/`）
//
// 与盲人端 `BlindOrderTopBar` 同一个样子（颜色、尺寸都读 `BlindOrderV7Palette` / `BlindOrderTopBarMetrics`），差在三处：
// - 没有「重复当前状态」喇叭：那是盲人端每页必有的入口，陪跑员端从来没有；
// - 「···」里装的是陪跑员的次要操作（我去不了、不合适、未接到来电）加举报 / 不再匹配此人；
// - identifier 沿用 v2 订单页顶栏那几个，守着它们的 UI 用例不用换判据。
//
// **这个组件不判订单状态**：求助走云端还是本地拨号由调用方传 `isCloudHelp`，
// 判定只在 `VolunteerOrderSOSMode.resolve` 一处（AGENTS §6）。

/// 「···」里陪跑员自己的一项。`kind` 只决定 identifier（守卫 `stale-ui-test-identifier` 只认字面量）。
struct VolunteerOrderMenuItem: Identifiable {
    enum Kind: String {
        /// 约好 / 出发态的「我去不了」。
        case releaseOrder
        /// 通话页的「不合适」。
        case introCallDecline
        /// 通话页的「未接到来电」。
        case introCallUnreachable
    }

    let kind: Kind
    let title: String
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void

    var id: String { kind.rawValue }
}

struct VolunteerOrderTopBar: OrderV7TopBar {
    let surface: BlindOrderBarSurface
    let onBack: () -> Void
    /// `false` = 不画返回（完成页的出口是主按钮「完成」）。
    var showsBack = true
    var menu: [VolunteerOrderMenuItem] = []
    /// 非 `nil` = 「···」末尾加举报 / 不再匹配此人。有没有对方由宿主判（`CounterpartSafetyGate`）。
    var counterpartSafety: CounterpartBlockViewModel?
    /// 只决定胶囊的样子与读屏说法；点下去做什么由 `onHelp` 决定。
    let isCloudHelp: Bool
    var isHelpBusy = false
    let onHelp: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if showsBack {
                backButton
            }
            Spacer(minLength: 0)
            if !menu.isEmpty || counterpartSafety != nil {
                moreMenu
            }
            VolunteerOrderHelpPill(surface: surface, isCloud: isCloudHelp, isBusy: isHelpBusy, action: onHelp)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: BlindOrderTopBarMetrics.hitSize)
        // 读屏顺序就是视觉顺序：返回 → ··· → 求助。
        .accessibilityElement(children: .contain)
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                if surface == .onDark {
                    Text("返回").flowFont(FlowV2Fonts.body())
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
        .accessibilityLabel("返回")
        .accessibilityIdentifier("volunteerOrderNavBackButton")
    }

    private var moreMenu: some View {
        Menu {
            ForEach(menu) { item in
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                    Text(item.title)
                }
                .disabled(!item.isEnabled)
                .modifier(VolunteerOrderMenuItemIdentifier(kind: item.kind))
            }
            if let counterpartSafety {
                CounterpartSafetyMenuItems(viewModel: counterpartSafety)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(surface == .onDark ? .white : AppColors.Flow.primaryText)
                .frame(width: BlindOrderTopBarMetrics.visibleSize, height: BlindOrderTopBarMetrics.visibleSize)
                .background(roundBackground)
                .padding((BlindOrderTopBarMetrics.hitSize - BlindOrderTopBarMetrics.visibleSize) / 2)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
        .accessibilityHint(menuTitles.joined(separator: "、"))
        .accessibilityIdentifier("volunteerOrderNavMoreMenu")
    }

    private var menuTitles: [String] {
        menu.map(\.title) + (counterpartSafety.map { CounterpartSafetyMenu.titles(viewModel: $0) } ?? [])
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

/// 右上角「求助」。样子同盲人端 `BlindOrderHelpPill`：深色头上透明底粉描边；地图上白底红字；
/// `isCloud`（只有 `IN_PROGRESS`）红底白字。读屏说法与 identifier 沿用 v2 的 `FlowHelpPill`。
struct VolunteerOrderHelpPill: View {
    let surface: BlindOrderBarSurface
    let isCloud: Bool
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().tint(ink)
                } else {
                    Image(systemName: "shield")
                        .font(.system(size: 15, weight: .semibold))
                }
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
        .disabled(isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .modifier(VolunteerHelpPillAccessibility(isCloud: isCloud))
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

/// 两种求助各自的读屏说法与 identifier（字面量分支，理由同 `OrderFlowBottomActions.Owner`）。
private struct VolunteerHelpPillAccessibility: ViewModifier {
    let isCloud: Bool

    func body(content: Content) -> some View {
        if isCloud {
            content
                .accessibilityLabel(VolunteerRunCopy.navButtonLabel)
                .accessibilityIdentifier("volunteerServiceSOSButton")
        } else {
            content
                .accessibilityLabel("求助与安全")
                .accessibilityIdentifier("volunteerOrderHelpPill")
        }
    }
}

/// 菜单项 identifier：沿用 v2 底部那几枚按钮的，守着「入口在不在」的 UI 用例只多一步「先开 ···」。
private struct VolunteerOrderMenuItemIdentifier: ViewModifier {
    let kind: VolunteerOrderMenuItem.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .releaseOrder: content.accessibilityIdentifier("volunteerOrderFlowRow-release")
        case .introCallDecline: content.accessibilityIdentifier("volunteerIntroCallDeclineButton")
        case .introCallUnreachable: content.accessibilityIdentifier("volunteerIntroCallUnreachableButton")
        }
    }
}
