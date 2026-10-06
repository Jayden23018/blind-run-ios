import SwiftUI

// MARK: - 订单页五幕的共用骨架

/// 匹配 / 约好 / 出发 / 汇合 / 倒计时 / 跑步中共用的**同一个**页面。
///
/// 🔄 2026-10-06（#349）跑步前四屏 + 倒计时改用陪跑员订单页 v2 的版式：
/// 浅色头卡（小标题 + 引导绳 + 大字 + 副文）→ 陪跑员卡 → 集合地点行 → 信息卡 → 底部两个按钮。
/// 四格进度条去掉，「第 N 步，共 4 步」由引导绳的读屏标签承担（`RopeState`，跑者视角）。
/// 头卡内容由 `BlindOrderHero` 算，它只从 `BlindOrderFlowPresentation` 派生，不新造判定。
/// 负责人同日拍板的三条不变：底部「求助与安全」不挪到右上角、头卡用浅色、跑步中仍原地变形。
///
/// **每一块的位置都不变**，只换内容；而**主按钮的位置一格不动，只换文字与图标**。
/// 这是设计稿最核心的一条：视障用户靠位置记忆操作，而改版前每个状态是独立页面 ——
/// iOS 切页时 VoiceOver 会把焦点移回第一个元素，读屏用户每次都要从头找。
/// 单页原地更新让焦点保持不动，只播报变化。
///
/// 2026-09-16 把 `IN_PROGRESS` 也收进来（原先是一整屏独立的深底执行屏）。
/// 开跑那一刻：头卡、陪跑员卡、地点行、信息卡整块换成跑步卡（顶行「陪跑中 · 张伟」+ 三个数字），
/// 同一页、同一条动画，焦点不跳顶。v1 那条头像 ⌀92 → ⌀28 的 `matchedGeometryEffect`
/// 随 v1 视觉区一起去掉了 —— v2 头卡里没有那枚大头像可以缩。
///
/// 外壳（可滚动卡片列 + 贴底操作区）是 `OrderFlowScaffold`。陪跑员端 v2 已改用自己的页面，
/// 现在只有这一页在用它；底栏「主按钮 + 求助与安全」两个版位保持不变。
/// 这一页保留的是**跑者端独有**的部分：倒计时、跑步中那三个数字、定位新鲜度行。
struct BlindOrderFlowView<Footer: View>: View {
    let presentation: BlindOrderFlowPresentation
    let order: OrderDetailResponse
    /// 跑步中那三个数字。其余相位用不到，传 `nil` 即可。
    var stats: TrackStats?
    /// 顶行右侧的定位新鲜度。
    ///
    /// 🔴 **这一行是刻意保留的偏离。** 设计稿只给了「按播报时追加一句」，而那条通道对
    /// 不开读屏的低视力用户等于不存在 —— 他们唯一能**看见** GPS 状态的地方就是这里
    /// （项目负责人 2026-09-16 决策 1 ①，记忆 `low-vision-visual-channel-unaudited`）。
    var isLocationFresh: Bool = true
    /// 集合地点那一行点下去做什么。`nil` = 不可点（拿不到地点时）。
    let onOpenStartPlace: (() -> Void)?
    let onLastRowTapped: () -> Void
    let onPrimaryAction: () -> Void
    let onOpenSafetyHub: () -> Void
    /// 「给陪跑员留言」那一行点下去做什么。`nil` = 这一态不能留言，整行不出现
    /// （判据 `RunOrderStatus.acceptsRunnerMessage`）。
    var onEditRunnerMessage: (() -> Void)? = nil
    /// 信息列表之后那块**「刚才那一下的结果」**。正常状态下是空的。
    ///
    /// 🔴 **它不是可选装饰。** 骨架把改版前那条滚动列表整段换掉了，而那条列表末尾挂着
    /// 这一页唯一的**可见**失败面（`viewModel.errorMessage`）与实时分享的结果提示。
    /// 少了它，「继续等待失败」「分享链接没生成」这类事只剩一句 TTS ——
    /// 不开读屏的低视力用户屏幕上零变化，而这正是记忆
    /// `claimed-fallback-may-not-exist-in-release` 里最常见的一种吃法。
    ///
    /// 放在信息列表**之后**而不是状态卡里：状态卡是「这一单现在怎么样」，
    /// 这里是「我刚按的那一下怎么样」，两件事混进一个合成元素会让读屏念不清是哪个。
    @ViewBuilder let footer: () -> Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 头卡。跑步中 / 已完成是 `nil`（那两幕画跑步卡）。
    private var hero: BlindOrderHero? {
        BlindOrderHero.make(presentation: presentation, order: order)
    }

    var body: some View {
        OrderFlowScaffold(bottom: bottomActions) {
            if presentation.phase.showsRunCard {
                runCard
            } else {
                if let hero { heroCard(hero) }
                volunteerCard
                placeCard
                // 跑起来之后这几块整块下沉淡出 —— 「陪跑员是谁、几点、在哪集合」
                // 全部已经是过去时，留在屏幕上只是读屏要多滑几次的内容。
                // 已完成同理，且它把「陪跑员是谁」以一行的形式留在了跑步卡里。
                infoCard
            }
            footer()
        }
        // 整段变形由同一条动画驱动：头卡换成跑步卡、下面几块下沉、主体拉高
        // 必须同时发生（设计稿 §Interactions 第 2 条），各自挂各自的动画会散成几拍。
        //
        // 挂在骨架外面与挂在它内部的 `VStack` 上等价（修饰符向下传播），
        // 而 `phase` 是跑者端独有的维度，不该进共用骨架的参数表。
        .animation(transitionAnimation, value: presentation.phase)
    }

    /// 变形动效。「减弱动态效果」打开时**返回 `nil`，整段瞬时切换**。
    ///
    /// 🔴 这里刻意**没有**照设计稿写「300ms 淡入淡出」，因为在 SwiftUI 里做不到它真正的意思。
    /// 挂上任何一条非 nil 动画，`if phase.isRunning` 那两处分支切换与信息卡整块移除带来的
    /// **高度塌缩**就会跟着插值：进度条那一格会撑开/收起，footer 会在 300ms 里往上滑约 240pt。
    /// 也就是说「淡入淡出」到不了，只能得到一次更短的位移 —— 而晕动症用户要躲的正是位移。
    /// 换更短的时长是在把违规做得不那么明显，不是在修它。
    ///
    /// **但倒计时保留** —— 它是信息不是装饰：三个数字仍然一拍一拍出现（由那 1 秒的
    /// 节拍驱动，不由动画驱动），只是不再回弹。
    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: BlindRunTransition.duration)
    }

    // MARK: - 头卡（跑步前四屏 + 倒计时）

    /// 浅色头卡（负责人 2026-10-06）。读屏顺序：引导绳（「第 N 步，共 4 步」，接替 v1 进度条）
    /// → 头卡正文（这一页最重要的那个元素）。
    private func heroCard(_ hero: BlindOrderHero) -> some View {
        FlowHeroCard(style: .light) {
            // 小标题画在绳子上面（与陪跑员端同一个排法），但**不单独进读屏** ——
            // 它已经是正文合成标签的第一句，单独一站会被念两遍。
            Text(hero.eyebrow)
                .flowFont(FlowV2Fonts.subhead(bold: true))
                .foregroundColor(AppColors.Flow.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            RopeView(
                state: hero.rope,
                theme: .light,
                volunteerInitial: volunteerInitial,
                perspective: .runner
            )
            // 限宽：绳子按 342×56 等比铺满容器，横屏下会长成占满整张头卡的大图，
            // 把正文挤到滚动区底边以外（2026-10-06 横屏审计因此判「正在匹配陪跑员」对比度不足 ——
            // 取到的是被切开的半行字）。竖屏容器本来就比这个窄，不受影响。
            .frame(maxWidth: RopeGeometry.width * 1.2)
            .frame(maxWidth: .infinity)
            heroBody(hero)
        }
    }

    private func heroBody(_ hero: BlindOrderHero) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let number = hero.number {
                heroNumber(number, unit: hero.unit, beat: hero.countdownBeat)
            }
            if let headline = hero.headline {
                // AX5 下会长到一百多 pt，必须允许换行 —— `lineLimit(1)` 等于把这一屏最重要的一行裁掉。
                Text(headline)
                    .flowFont(FlowV2Fonts.title())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(hero.lines, id: \.self) { line in
                Text(line)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 只在异常时出现。正常状态**不显示任何「定位正常」之类的反向提示**。
            if let warning = hero.warning {
                Text(warning)
                    .flowFont(FlowV2Fonts.callout(bold: true))
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 🔴 正文合成**一个**元素，而且是这一页最重要的那个。
        // 拆开的后果是读屏用户要滑几次才听全「现在是什么情况」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityLabel)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    /// 主角数字。约好态是开跑钟点，倒计时是「3」「2」「1」。
    ///
    /// 倒计时每拍换一个数字 ⇒ `id` 变 ⇒ 这个视图被换掉一次 ⇒ `transition` 重新播一次回弹。
    /// 「减弱动态效果」下换成纯淡入淡出：不缩放、不位移，**但三个数字照样一拍一拍出现**。
    @ViewBuilder
    private func heroNumber(_ number: String, unit: String?, beat: Int?) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(number).flowHeroNumber(beat == nil ? FlowV2Fonts.heroM : FlowV2Fonts.heroXL)
            if let unit {
                Text(unit).flowFont(FlowV2Fonts.heroUnit())
            }
        }
        .foregroundColor(beat == nil ? AppColors.Flow.primaryText : AppColors.Flow.accent)

        if let beat {
            row
                .id(beat)
                .animation(
                    reduceMotion ? nil : .spring(response: BlindRunCountdown.bounceResponse, dampingFraction: 0.55),
                    value: beat
                )
                .transition(reduceMotion ? .opacity : .scale(scale: BlindRunCountdown.bounceScale).combined(with: .opacity))
        } else {
            row
        }
    }

    /// 引导绳上陪跑员头像里的字：姓氏（去掩码），拿不到时写「陪」。
    private var volunteerInitial: String {
        order.volunteerName?.unmaskedForSpeech.first.map(String.init) ?? "陪"
    }

    // MARK: - 陪跑员卡 / 集合地点

    /// 与陪跑员端「跑者卡」同一个组件，换成陪跑员视角（`role: "陪跑员"`）。
    /// 还没有陪跑员（匹配中、通话磨合中 `order.volunteer` 恒为 null）时整块不画 ——
    /// 头卡已经在说「正在匹配」，再画一张「正在匹配」的卡只是多一站读屏。
    ///
    /// ⚠️ 设计稿 v1 这里是「张伟，已认证」。**「已认证」不显示** ——
    /// 订单详情里没有这个字段（契约里 0 命中）。无字段却印「已认证」是伪造信任标识。
    @ViewBuilder
    private var volunteerCard: some View {
        if hasVolunteer {
            FlowRunnerCard(
                name: volunteerDisplayName,
                detail: order.volunteerExperienceText ?? "",
                role: "陪跑员"
            )
        }
    }

    /// 能打开地图时画成 v2 的地点行；否则退回信息卡里一条不可点的行（见 `infoCard`）。
    ///
    /// ⚠️ 截至 #349，订单页唯一的调用点（`BlindOrderStatusView`）**恒传 `nil`** —— 盲人端还没有
    /// 「打开地图」这个动作，所以真机上集合地点是信息卡里那一行。给盲人端加地图入口是另一个需求。
    /// Preview 也传 `nil`，否则截图评审看到的是一个生产里不存在的版式。
    @ViewBuilder
    private var placeCard: some View {
        if let onOpenStartPlace {
            FlowPlaceRow(
                systemImage: "mappin",
                title: placeText,
                accessibilityPrefix: "集合地点",
                action: onOpenStartPlace
            )
            .accessibilityIdentifier("blindOrderFlowPlaceRow")
        }
    }

    // MARK: - 跑步卡（跑步中 / 已完成）

    private var runCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                partnerRow
                FlowSeparator()
                BlindActiveRunView(stats: stats, paceLabel: paceLabel)
                // ④ 比 ③ 多这一行「陪跑员 张伟」（设计稿 §4）。跑动中不显示 ——
                // 那一刻人就在身边，而这一行会把三个数字往上挤。
                if presentation.phase == .finished {
                    FlowSeparator()
                    partnerSummaryRow
                }
            }
        }
    }

    /// ③「配速」/ ④「平均配速」。两处的数其实是同一个均值，差别是跑完之后
    /// 「平均」才有信息（跑动中说「平均」会让人找一个不存在的「当前配速」）。
    private var paceLabel: String {
        BlindRunCopy.metricPaceLabel(isFinished: presentation.phase == .finished)
    }

    /// ④ 卡片底部那一行。姓名**视觉上保留掩码、朗读去掩码**（同 `volunteerRow`）。
    ///
    /// 不显示陪跑经验：稿上这一行只有姓名，而跑完之后「陪跑 32 次」回答的是
    /// 「要不要把自己交给他」—— 那个决定已经做完了。
    private var partnerSummaryRow: some View {
        FlowInfoRow(
            label: BlindRunCopy.partnerSummaryLabel,
            accessibilityLabel: "\(BlindRunCopy.partnerSummaryLabel)\(order.volunteerNameForSpeech)"
        ) {
            Text(volunteerDisplayName)
                .flowFont(FlowFonts.rowValueEmphasized())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("blindOrderFlowFinishedPartnerRow")
    }

    // MARK: - 跑步中 / 已完成的顶行

    /// 小头像 ⌀28 + 「陪跑中 · 张伟」/「已完成 · 张伟」 + 定位新鲜度。
    ///
    /// 两条信息是**两个独立的无障碍元素**：读屏用户第一站听搭档是谁，第二站听定位好不好，
    /// 合成一个会让「定位信号弱」被埋在一句长话的尾巴上。
    private var partnerRow: some View {
        HStack(spacing: 10) {
            FlowAvatar(
                name: order.volunteerName,
                diameter: FlowMetrics.partnerAvatarDiameter,
                background: AppColors.Flow.avatarBackground,
                foreground: AppColors.Flow.avatarInitial
            )
            Text(presentation.title)
                .flowFont(FlowFonts.partnerHeadline())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blindOrderFlowPartnerHeadline")

            Spacer(minLength: 8)

            // 🔴 **跑完之后这枚徽标不出现。** 「定位信号弱」在 ④ 没有任何可执行的动作
            // （跑都跑完了），而它会占掉读屏一站、也占掉顶行右侧那块给姓名换行的宽度。
            // 跑步中保留的理由反过来说明了这一点：那一刻用户能换个开阔地方站一站。
            if presentation.phase != .finished {
                locationFreshnessBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FlowMetrics.partnerRowHorizontalPadding)
        .padding(.vertical, FlowMetrics.partnerRowVerticalPadding)
    }

    /// 🚩 判的是**本机定位新不新鲜**，不是后端的 `ESCORT_SIGNAL_LOST`。那条事件是一次性
    /// 告警（`AppRealtimeCoordinator.routeEscortAlert`），没有可以持续读的状态；
    /// 而用户看到这一行能做的事（换个开阔地方、检查权限）恰恰只跟本机定位有关。
    ///
    /// 措辞是「信号弱」不是「定位失败」：权限正常但在室内 / 高楼间拿不到定位是常态，
    /// 说成失败会把人支去翻设置解决一个不存在的问题。
    private var locationFreshnessBadge: some View {
        HStack(spacing: 5) {
            // 圆点纯装饰：「几格信号」这种纯视觉编码读屏念不出来，状态由**文字**承担。
            // 圆点只是给看得见的人一个扫读锚点。
            //
            // 用 `AppColors.success/.warning` 而不是新造一对 `Flow` 色：它们是**语义色**
            // （好 / 需注意），正是这颗点要表达的东西，而 `Flow` 装的是表面色。
            // 压白卡 5.07 / 5.20，压深卡 8.42 / 8.28，四个方向都过线 —— 理由与量过的数
            // 记在 `AppColors.Flow` 里那段注释上。
            Circle()
                .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                .frame(width: FlowMetrics.locationDotDiameter, height: FlowMetrics.locationDotDiameter)
                .accessibilityHidden(true)
            Text(isLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale)
                .flowFont(FlowFonts.rowDetail())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindOrderFlowLocationFreshness")
    }

    // MARK: - 信息列表

    /// 陪跑员与可点的集合地点已经上移成独立的卡（`volunteerCard` / `placeCard`），这里只剩：
    /// 时间（读屏念完整日期，头卡小标题只有「明天早上」）、拿不到地点时的兜底行、留言、最后一行。
    private var infoCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                timeRow
                FlowSeparator()
                if onOpenStartPlace == nil {
                    placeRow
                    FlowSeparator()
                }
                if let onEditRunnerMessage {
                    runnerMessageRow(onEditRunnerMessage)
                    FlowSeparator()
                }
                lastRow
            }
        }
    }

    private var hasVolunteer: Bool { order.volunteerName?.nilIfBlank != nil }

    /// 姓名**视觉上保留掩码**（`张*`）、**朗读去掉星号**（`FlowRunnerCard` 内部走 `unmaskedForSpeech`）。
    private var volunteerDisplayName: String {
        order.volunteerName ?? ""
    }

    private var timeRow: some View {
        FlowInfoRow(label: "时间", accessibilityLabel: timeAccessibilityLabel) {
            Text(order.blindRunnerShortStartText() ?? "待确认")
                .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 读屏念完整日期而不是屏幕上那个「明天 7:00」：听的人没有屏幕可以回看，
    /// 含糊的相对日期反而要他自己换算。
    private var timeAccessibilityLabel: String {
        "时间，\(order.plannedStartForAnnouncement ?? order.blindRunnerShortStartText() ?? "待确认")"
    }

    private var placeRow: some View {
        FlowInfoRow(
            label: "集合地点",
            kind: onOpenStartPlace.map { .navigable(action: $0) } ?? .display,
            accessibilityLabel: "集合地点，\(placeText)",
            accessibilityHint: onOpenStartPlace == nil ? nil : "双击查看集合地点在地图上的位置"
        ) {
            Text(placeText)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
    }

    private var placeText: String {
        order.startAddress?.nilIfBlank ?? "出发地点待确认"
    }

    /// 出发前给陪跑员留的一句话。行内直接显示原文 —— 跑者要能听到自己留过什么。
    private func runnerMessageRow(_ action: @escaping () -> Void) -> some View {
        let message = order.messageToVolunteer?.nilIfBlank
        return FlowInfoRow(
            label: "留言",
            kind: .navigable(action: action),
            accessibilityLabel: message.map { "给陪跑员的留言，\($0)" } ?? "给陪跑员留言，还没有留",
            accessibilityHint: "双击写一句话给陪跑员，比如你穿什么衣服"
        ) {
            Text(message ?? "出发前留一句话")
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(message == nil ? AppColors.Flow.secondaryText : AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("blindOrderFlowRunnerMessageRow")
    }

    /// 最后一行：这一态的破坏性/求助入口。**固定位置、点击后二次确认。**
    ///
    /// 文案随状态变（取消匹配 / 取消预约 / 遇到问题），判据在
    /// `BlindOrderFlowPresentation.lastRowTitle`。
    private var lastRow: some View {
        FlowInfoRow(
            label: nil,
            kind: .navigable(action: onLastRowTapped),
            accessibilityLabel: presentation.lastRowTitle,
            accessibilityHint: "双击后会先确认一次"
        ) {
            Text(presentation.lastRowTitle)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("blindOrderFlowLastRowButton")
    }

    // MARK: - 底部操作区

    /// 主按钮（可能为空）+ 固定的「求助与安全」。
    ///
    /// 设计意图第 3 条：旧版把打电话、修改取消、求助三个按钮并排，重点不清。
    /// 这里只有两个版位，且第二个的文案与位置**永不变化** —— 视障用户靠位置记忆操作。
    ///
    /// 🔴 跑者端这一枚「求助与安全」**在每一态都给**（所以这里恒非 nil）。
    /// 陪跑员端不同，判据与理由见 `VolunteerOrderFlowPresentation.showsSafetyHub`。
    private var bottomActions: OrderFlowBottomActions {
        OrderFlowBottomActions(
            owner: .blindRunner,
            primary: presentation.primaryAction.map { action in
                OrderFlowPrimaryAction(
                    title: action.title,
                    systemImage: action.systemImage,
                    isEnabled: action.isEnabled,
                    accessibilityHint: primaryActionHint(action),
                    action: onPrimaryAction
                )
            },
            safetyHub: OrderFlowSafetyHubAction(action: onOpenSafetyHub)
        )
    }

    /// `nil` = 这一档不加提示。`FlowActionButton` 走 `accessibilityHintIfPresent`，
    /// 传空串会**覆盖**掉自动合成的提示，所以不能拿 `""` 当「没有」。
    private func primaryActionHint(_ action: BlindOrderFlowPresentation.PrimaryAction) -> String? {
        switch action {
        case .callVolunteer:
            // 刻意**不念号码**：VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，
            // 而视障跑者在户外常常不戴耳机（要听车流）—— 外放等于把陪跑员的号码
            // 广播给周围所有人。号码对「要不要打这通电话」没有任何帮助。
            return "系统会先弹出拨号确认，确认后才会拨出"
        case .openIntroCall:
            return IntroCallCopy.blindEntryAccessibilityHint
        case .keepWaiting:
            return KeepWaitingCopy.accessibilityHint
        case .startRun:
            return BlindRunCopy.startRunHint
        case .startRunLocked(let opensAt):
            return BlindRunCopy.startRunLockedHint(opensAt: opensAt)
        case .preparing:
            // 刻意不给提示。`.disabled()` 已经让读屏念「变暗」，再补一句「马上就可以按了」
            // 是在这三秒里往耳朵里多塞一条没有动作可做的信息。
            return nil
        case .announceStats:
            return BlindRunCopy.announceStatsHint
        case .done:
            // 「完成」两个字不说明按下去会发生什么 —— 而这一刻它是这一屏唯一的出口
            //（返回箭头按稿藏掉了）。
            return BlindRunCopy.finishedButtonHint
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("订单页 · 匹配中") {
    BlindOrderFlowPreview(status: .pendingMatch, volunteerName: nil)
}

#Preview("订单页 · 已约好") {
    BlindOrderFlowPreview(status: .scheduledConfirmed)
}

#Preview("订单页 · 出发中") {
    BlindOrderFlowPreview(status: .driverEnRoute, distanceText: "距出发地点约 600 米")
}

#Preview("订单页 · 已汇合") {
    BlindOrderFlowPreview(status: .driverArrived)
}

#Preview("订单页 · 倒计时") {
    BlindOrderFlowPreview(status: .inProgress, countdown: 3)
}

#Preview("订单页 · 跑步中") {
    BlindOrderFlowPreview(status: .inProgress, stats: .previewRunning)
}

#Preview("订单页 · 跑步中 · 定位信号弱") {
    BlindOrderFlowPreview(status: .inProgress, stats: .previewRunning, isLocationFresh: false)
}

#Preview("订单页 · 已完成") {
    BlindOrderFlowPreview(status: .completed, stats: .previewFinished)
}

#Preview("订单页 · 已完成 · AX5") {
    BlindOrderFlowPreview(status: .completed, stats: .previewFinished)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("订单页 · 已完成 · 深色") {
    BlindOrderFlowPreview(status: .completed, stats: .previewFinished)
        .preferredColorScheme(.dark)
}

#Preview("订单页 · 跑步中 · AX5") {
    BlindOrderFlowPreview(status: .inProgress, stats: .previewRunning)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("订单页 · 已约好 · AX5") {
    BlindOrderFlowPreview(status: .scheduledConfirmed)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("订单页 · 出发中 · 深色") {
    BlindOrderFlowPreview(status: .driverEnRoute, distanceText: "距出发地点约 600 米")
        .preferredColorScheme(.dark)
}

/// Preview 共用的装配。抽成具名类型而不是抄十遍 —— 抄十遍改一处会漏九处，
/// 而 Preview 的漂移没有任何东西会报警。
private struct BlindOrderFlowPreview: View {
    let status: RunOrderStatus
    var volunteerName: String? = "张*"
    var distanceText: String?
    var countdown: Int?
    var stats: TrackStats?
    var isLocationFresh = true

    var body: some View {
        let order = OrderDetailResponse.preview(
            status: status,
            volunteerName: volunteerName,
            volunteerTotalCompleted: volunteerName == nil ? nil : 32,
            volunteerPhone: volunteerName == nil ? nil : "13800000001"
        )
        if let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: distanceText,
            canKeepWaiting: false,
            countdown: countdown
        ) {
            BlindOrderFlowView(
                presentation: presentation,
                order: order,
                stats: stats,
                isLocationFresh: isLocationFresh,
                // 与生产调用点一致（见 `placeCard`）。
                onOpenStartPlace: nil,
                onLastRowTapped: {},
                onPrimaryAction: {},
                onOpenSafetyHub: {},
                footer: { EmptyView() }
            )
        } else {
            Text("这一态不走四步骨架：\(status.rawValue)")
        }
    }
}
#endif
