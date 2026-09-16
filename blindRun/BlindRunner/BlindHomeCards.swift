import SwiftUI

// MARK: - 首页深蓝订单卡

/// 首页最大的那一块：即将开始的那一单。
///
/// **整张卡是一个按钮，也是一个无障碍元素。** 这是这一屏最重要的设计决策：
/// 视障用户打开 App 第一句听到的就该是最重要的信息，而且是**一句完整的话**，
/// 不是被拆成时间、地点、姓名、小按钮好几段各滑一次。
///
/// 所以 `children: .ignore` + 手写 `accessibilityLabel`，不用 `.combine`：
/// 自动拼接会把「陪跑员」「张*」「陪跑 32 次」串成一长条，且星号会被念成「星号」。
///
/// 卡片内容**跟随订单实时状态变化**（状态小字、大字时间、陪跑员段三处），
/// 数据源就是首页 view model 的 `activeOrder`，WebSocket 推进时它自己会变。
struct BlindHomeOrderCard: View {
    let order: OrderDetailResponse
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(statusCaption)
                    .flowFont(FlowFonts.homeCardCaption())
                    .foregroundColor(AppColors.Flow.onNavySecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(timeText)
                    .flowFont(FlowFonts.homeCardTime(), monospacedDigit: true)
                    .foregroundColor(.white)
                    // 52pt 的大字在 AX5 下会长到一百多 pt，必须允许换行 ——
                    // `lineLimit(1)` 在这里等于「把最重要的一行裁掉」。
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                placeRow
                    .padding(.top, 10)

                volunteerRow
                    .padding(.top, 18)

                openOrderFooter
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowMetrics.homeCardPadding)
            .padding(.top, FlowMetrics.homeCardPadding)
            .padding(.bottom, FlowMetrics.homeCardBottomPadding)
            .background(AppColors.Flow.navy)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeCardRadius, style: .continuous))
            .flowCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("双击打开订单，查看进度并联系陪跑员")
        .accessibilityIdentifier("blindRunnerHomeOrderCard")
    }

    // MARK: 视觉

    private var placeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 18, weight: .regular))
                .accessibilityHidden(true)
            Text(placeText)
                .flowFont(FlowFonts.homeCardPlace())
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(AppColors.Flow.onNavyTertiary)
    }

    private var volunteerRow: some View {
        HStack(spacing: 12) {
            if order.volunteerName?.nilIfBlank != nil {
                // 传掩码原串而不是朗读版：`FlowAvatar` 只取首字，`张*` 与 `张` 得到同一个
                // 「张」，而朗读版在空名字时会回退成「这位志愿者」——首字是「这」。
                // 这里有 `volunteerName != nil` 的外层守卫，但别依赖调用方的守卫来保证取值合法。
                FlowAvatar(
                    name: order.volunteerName,
                    diameter: FlowMetrics.homeVolunteerAvatarDiameter,
                    background: AppColors.Flow.navyAvatar,
                    foreground: .white
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(volunteerTitle)
                    .flowFont(FlowFonts.homeCardRowTitle())
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let experience = order.volunteerExperienceText {
                    Text(experience)
                        // 等宽数字：与上面 52pt 大字同一套口径，需求第 8 条要求全部数字等宽。
                        .flowFont(FlowFonts.homeCardRowDetail(), monospacedDigit: true)
                        .foregroundColor(AppColors.Flow.onNavySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .overlay(alignment: .top) {
            // 卡片内的分隔线。压在深蓝上，所以用白色低透明度而不是 `Flow.separator`
            // （那个是给白卡准备的，压在深蓝上完全看不见）。
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// 底部那条半透明白底「打开订单 ›」。
    ///
    /// **它不是独立按钮** —— 整张卡已经是一个按钮了，再套一个会让读屏用户在同一张卡上
    /// 遍历到两个都叫「打开订单」的元素。它的作用只有一个：告诉**看得见**的用户这张卡可以点。
    /// 所以对读屏隐藏，动作由卡片的 `accessibilityHint` 说明。
    private var openOrderFooter: some View {
        HStack {
            Text("打开订单")
                .flowFont(FlowFonts.homeCardRowTitle())
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: FlowMetrics.navyFooterMinHeight) // guard:allow small-touch-target
        .background(
            Color.white.opacity(0.1),
            in: RoundedRectangle(cornerRadius: FlowMetrics.navyFooterRadius, style: .continuous)
        )
        .accessibilityHidden(true)
    }

    // MARK: 文案

    /// 状态小字。
    ///
    /// 🔴 **「下一次陪跑」只对还没开始的那几态成立。** 设计稿只画了 `SCHEDULED_CONFIRMED`
    /// 一态，而 `isActiveForBlindRunner` 还包含 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` /
    /// `IN_PROGRESS` —— 陪跑进行中时念「下一次陪跑，进行中」，是把正在发生的事说成未来。
    /// 读屏用户听到的是这一屏的第一句话，说错了整屏的语义就错了。
    private var statusCaption: String {
        order.status.isUnderwayForBlindRunner
            ? order.status.displayName
            : "下一次陪跑，\(order.status.displayName)"
    }

    /// 52pt 的那行大字。
    ///
    /// 🔴 **已经出发之后不再显示计划开始时刻。** 那个时间已经过去了，而它占的是这一屏
    /// 最大的位置 —— 走绝对日期分支念出「9月16日 7:00」，等于把黄金位置给了一个
    /// 用户此刻完全不需要的数字。改成念这一态本身（「志愿者已到达」/「进行中」）。
    ///
    /// 时间拿不到时同理**不显示占位时间**：摆一个「--:--」出来，位置就被一个
    /// 没有信息的东西占住了。
    private var timeText: String {
        if order.status.isUnderwayForBlindRunner {
            return order.status.displayName
        }
        return order.blindRunnerShortStartText() ?? order.status.displayName
    }

    private var placeText: String {
        order.startAddress?.nilIfBlank ?? "出发地点待确认"
    }

    /// 还没有陪跑员时说「正在匹配陪跑员」，而不是留空或摆一个灰头像 ——
    /// 这一行在等待期是用户最想知道的那件事。
    private var volunteerTitle: String {
        guard order.volunteerName?.nilIfBlank != nil else { return "正在匹配陪跑员" }
        return "陪跑员 \(order.volunteerName ?? "")"
    }

    /// 合并后的那一句话。顺序 = 用户关心的顺序：这是什么 → 什么时候 → 在哪 → 和谁。
    ///
    /// 时间用 `plannedStartForAnnouncement`（完整日期）而不是屏幕上那个「明天 7:00」：
    /// 听的人没有屏幕可以回看，含糊的相对日期反而要他自己换算。见
    /// `blindRunnerShortStartText` 的注释。
    private var accessibilityLabel: String {
        var parts = ["\(statusCaption)。"]
        // 已经出发之后不念计划开始时刻 —— 与大字同一条理由（那个时间已经过去了）。
        if !order.status.isUnderwayForBlindRunner, let spoken = order.plannedStartForAnnouncement {
            parts.append("\(spoken)，")
        }
        parts.append("\(placeText)。")
        if order.volunteerName?.nilIfBlank != nil {
            var volunteer = "陪跑员\(order.volunteerNameForSpeech)"
            if let experience = order.volunteerExperienceText {
                volunteer += "，\(experience)"
            }
            parts.append("\(volunteer)。")
        } else {
            parts.append("正在匹配陪跑员。")
        }
        return parts.joined()
    }
}

// MARK: - 首页预约入口

/// 浅蓝预约块。**整块是一个按钮**，同 `BlindHomeOrderCard`。
///
/// 没有待进行订单时它移到订单卡的位置（由调用方的布局决定，这个组件不关心）。
struct BlindHomeBookingBlock: View {
    /// `false` 时按下去只解释「订单状态还没确认」，不进下单页 —— 避免创建重复预约。
    /// 这个闸在改版前就有（`BlindRunnerHomeViewModel.canStartNewBooking`），照搬不动。
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: FlowMetrics.bookingPlusDiameter, height: FlowMetrics.bookingPlusDiameter)
                    .background(AppColors.Flow.accent, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("预约新的陪跑")
                        .flowFont(FlowFonts.bookingTitle())
                        .foregroundColor(AppColors.Flow.bookingTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("选好时间和地点，系统帮你找陪跑员")
                        .flowFont(FlowFonts.bookingSubtitle())
                        .foregroundColor(AppColors.Flow.bookingSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppColors.Flow.bookingTitle)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowMetrics.bookingBlockHorizontalPadding)
            .padding(.vertical, FlowMetrics.bookingBlockVerticalPadding)
            .background(AppColors.Flow.bookingBackground)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isEnabled ? "预约新的陪跑" : "预约新的陪跑，订单状态尚未确认")
        .accessibilityHint(accessibilityHint)
        .modifier(BookingBlockIdentifier(isEnabled: isEnabled))
    }

    /// 视觉副标题只说「选好时间和地点」，而**按下去真正发生的事是开始录音**。
    ///
    /// 所以 hint 不能照抄副标题：看得见的人按下去会看到麦克风界面，看不见的人只有这一句话
    /// 可以依据。改版前那个 hint 写全了这件事，这里保留 —— 丢掉它是可发现性的实打实回退。
    private var accessibilityHint: String {
        guard isEnabled else { return "双击后说明如何先确认当前订单状态" }
        return "选好时间和地点，系统帮你找陪跑员。双击后进入语音下单：说一句想什么时候跑、跑多久，"
            + "听完复述再确认；也可以改用表单填写"
    }
}

/// 预约块的 identifier，两个状态两个值，都与改版前逐字相同。
///
/// 🔴 **必须写成两个字面量分支，不能写成 `.accessibilityIdentifier(cond ? "a" : "b")`。**
/// `scripts/hooks/guard.mjs` 的 `stale-ui-test-identifier` 扫的是
/// `accessibilityIdentifier(\s*"字面量"\s*)` —— 三元表达式它一个都抓不到，于是
/// 「UI 测试引用的 id 在 App 侧存不存在」这道双向校验对这两个 id 直接失效。
/// 失效的表现是**没有表现**：正面断言照常红，反面断言恒真等于没写，而 CI 跑不了 XCTest。
private struct BookingBlockIdentifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityIdentifier("blindRunnerHomeStartBookingButton")
        } else {
            content.accessibilityIdentifier("blindRunnerHomeStartBookingGuardButton")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("首页内容 · 有订单 · 默认字号") {
    BlindHomeCardsPreview(hasOrder: true)
}

#Preview("首页内容 · 有订单 · AX5") {
    BlindHomeCardsPreview(hasOrder: true)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("首页内容 · 无订单 · 默认字号") {
    BlindHomeCardsPreview(hasOrder: false)
}

#Preview("首页内容 · 无订单 · AX5") {
    BlindHomeCardsPreview(hasOrder: false)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("首页内容 · 匹配中 · 深色") {
    BlindHomeCardsPreview(hasOrder: true, status: .pendingMatch, volunteerName: nil)
        .preferredColorScheme(.dark)
}

/// 四个 Preview 共用的内容。抽成具名类型而不是抄四遍：抄四遍改一处就会漏三处，
/// 而 Preview 的漂移没有任何东西会报警。
private struct BlindHomeCardsPreview: View {
    let hasOrder: Bool
    var status: RunOrderStatus = .scheduledConfirmed
    var volunteerName: String? = "张*"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("你好，李明")
                    .flowFont(FlowFonts.homeGreeting())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .padding(.horizontal, 4)
                    .padding(.top, 18)

                if hasOrder {
                    BlindHomeOrderCard(
                        order: .preview(
                            status: status,
                            volunteerName: volunteerName,
                            volunteerTotalCompleted: volunteerName == nil ? nil : 32
                        ),
                        action: {}
                    )
                    .padding(.top, 6)
                }

                BlindHomeBookingBlock(isEnabled: true, action: {})
            }
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .padding(.bottom, 28)
        }
        .background(AppColors.Flow.page)
    }
}
#endif
