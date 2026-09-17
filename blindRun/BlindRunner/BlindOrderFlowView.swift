import SwiftUI

/// 头像那一路变形的 geometry id。
///
/// 放在文件作用域而不是 `BlindOrderFlowView` 里：那个类型对 `Footer` 泛型，
/// 而 Swift 不允许泛型类型有 static 存储属性。
private let blindOrderFlowAvatarGeometryID = "blindOrderFlowVolunteerAvatar"

// MARK: - 订单页五幕的共用骨架

/// 匹配 / 约好 / 出发 / 汇合 / 倒计时 / 跑步中共用的**同一个**骨架：
/// 进度条（跑步中折叠成一行）→ 视觉区 → 状态标题副标题（跑步中换成三个数字）
/// → 信息列表（跑步中移除）→ 底部两个按钮。
///
/// **每一块的位置都不变**，只换内容；而**主按钮的位置一格不动，只换文字与图标**。
/// 这是设计稿最核心的一条：视障用户靠位置记忆操作，而改版前每个状态是独立页面 ——
/// iOS 切页时 VoiceOver 会把焦点移回第一个元素，读屏用户每次都要从头找。
/// 单页原地更新让焦点保持不动，只播报变化。
///
/// 2026-09-16 把 `IN_PROGRESS` 也收进来（原先是一整屏独立的深底执行屏）。
/// 变形的三条动效都在这里：进度条上折 / 头像 ⌀92 →  ⌀28 同一个视图在动 / 信息卡下沉淡出。
///
/// 2026-09-17 外壳（可滚动卡片列 + 贴底操作区）搬进 `OrderFlowScaffold`，与陪跑员端共用 ——
/// 两端的四步进度条只有第 1 步文案不同，底部版位完全一致（设计交付文档 v3 §9）。
/// 这一页保留的是**跑者端独有**的部分：头像变形、倒计时、跑步中那三个数字、定位新鲜度行。
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

    /// 头像那一路变形的 geometry 命名空间。⌀92 与 ⌀28 是**同一个视图在动**。
    @Namespace private var avatarTransition

    var body: some View {
        // 布局骨架取 main 上抽出来的 `OrderFlowScaffold`（陪跑员端 PR #155 起与跑者端共用），
        // 判据取本轮的 `showsRunCard` —— 两边改的不是同一件事，合并时两个都要留。
        OrderFlowScaffold(bottom: bottomActions) {
            statusCard
            // 信息卡整块下沉淡出并收到 0 —— 跑起来之后「陪跑员是谁、几点、在哪集合」
            // 全部已经是过去时，留在屏幕上只是读屏要多滑四次的内容。
            // 已完成同理，且它把「陪跑员是谁」以一行的形式留在了状态卡里。
            if !presentation.phase.showsRunCard {
                infoCard
            }
            footer()
        }
        // 整段变形由同一条动画驱动：进度条上折、头像缩移、信息卡下沉、主体拉高
        // 必须同时发生（设计稿 §Interactions 第 2 条），各自挂各自的动画会散成四拍。
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
    /// 头像那条 `matchedGeometryEffect` 同样一并不挂（见 `matchedAvatarGeometry`）。
    /// **但倒计时保留** —— 它是信息不是装饰：三个数字仍然一拍一拍出现（由那 1 秒的
    /// 节拍驱动，不由动画驱动），只是不再回弹。
    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: BlindRunTransition.duration)
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                // 进度条向上折叠（高度 → 0、透明度 → 0），「陪跑中 · 张伟」在原位展开。
                if presentation.phase.showsRunCard {
                    partnerRow
                } else {
                    FlowStepper(
                        currentStep: presentation.step.rawValue,
                        titles: BlindOrderFlowStep.allTitles
                    )
                }
                FlowSeparator()
                if presentation.phase.showsRunCard {
                    BlindActiveRunView(stats: stats, paceLabel: paceLabel)
                    // ④ 比 ③ 多这一行「陪跑员 张伟」（设计稿 §4）。跑动中不显示 ——
                    // 那一刻人就在身边，而这一行会把三个数字往上挤。
                    if presentation.phase == .finished {
                        FlowSeparator()
                        partnerSummaryRow
                    }
                } else {
                    heroSection
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
            matchedAvatarGeometry(
                FlowAvatar(
                    name: order.volunteerName,
                    diameter: FlowMetrics.partnerAvatarDiameter,
                    background: AppColors.Flow.avatarBackground,
                    foreground: AppColors.Flow.avatarInitial
                )
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

    /// 头像从视觉区中央 ⌀92 缩小移到顶行左上 ⌀28 —— **同一个视图在动**，不是交叉淡入淡出。
    ///
    /// 「减弱动态效果」打开时**不挂这个修饰符**：挂着它就必然产生位移与缩放，
    /// 而那正是这个设置要消掉的东西。此时两枚头像各自淡入淡出，位置照常正确。
    @ViewBuilder
    private func matchedAvatarGeometry<V: View>(_ view: V) -> some View {
        if reduceMotion {
            view
        } else {
            view.matchedGeometryEffect(id: blindOrderFlowAvatarGeometryID, in: avatarTransition)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            visualArea
            Text(presentation.title)
                .flowFont(FlowFonts.statusTitle(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .multilineTextAlignment(.center)
                // 34pt 在 AX5 下会长到一百多 pt，必须允许换行 ——
                // `lineLimit(1)` 在这里等于把这一屏最重要的一行裁掉。
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FlowMetrics.statusTitleTopSpacing)

            Text(presentation.subtitle)
                .flowFont(FlowFonts.statusSubtitle())
                .foregroundColor(AppColors.Flow.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            // 只在异常时出现。正常状态**不显示任何「定位正常」之类的反向提示** ——
            // 那种提示对读屏用户是每次进页面都要滑过去的一条无信息内容。
            if let warning = presentation.warning {
                Text(warning)
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        // 🔴 标题 + 副标题（+ 警示）合成**一个**元素，而且是这一页最重要的那个。
        // 拆开的后果是读屏用户要滑两三次才听全「现在是什么情况」。
        // 视觉区在里面，但它 `accessibilityHidden`，不参与合成。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    /// 跑步中那一幕 `subtitle` 是空串，`joined` 会拼出一个多余的句号让读屏念一次停顿，
    /// 所以先滤空。**不要写成 `title + "。" + subtitle`** —— 那正是漏掉这一步的写法。
    private var statusAccessibilityLabel: String {
        var parts = [presentation.title, presentation.subtitle]
        if let warning = presentation.warning { parts.append(warning) }
        return parts.filter { !$0.isEmpty }.joined(separator: "。")
    }

    // MARK: - 视觉区（纯装饰，对读屏隐藏）

    /// 124×124 的方形区域。四态换内容但**尺寸不变** —— 骨架固定这条就落在这里：
    /// 下面的标题不会因为上面换了一种图形而上下跳。
    private var visualArea: some View {
        ZStack {
            switch presentation.visual {
            case .radar:
                radar
            case .avatar:
                avatar
            case .avatarWithProgressRing:
                avatar
                progressRing
            case .avatarWithSuccessBadge:
                avatar
                successBadge
            case .countdown(let beat):
                countdownCircle(beat)
            // 跑步中这一幕整个 `heroSection` 都不渲染（`statusCard` 直接换成三个数字），
            // 所以这里走不到。**留一个显式分支而不是 `default`** —— 加 `Visual` 时
            // 编译器会逼一次决策，而 `default` 会把新形态默默画成空白。
            case .runMetrics:
                EmptyView()
            }
        }
        .frame(width: FlowMetrics.visualSide, height: FlowMetrics.visualSide)
        // 整块纯装饰：状态信息在标题与副标题里有完整文字版。
        // 装饰内容的标准处理就是对辅助技术隐藏 —— 读屏用户 0 次多余划动就够到状态。
        .accessibilityHidden(true)
    }

    private var radar: some View {
        ZStack {
            Circle()
                .fill(AppColors.Flow.radarOuter)
                .overlay(Circle().strokeBorder(AppColors.Flow.radarOuterStroke, lineWidth: 1.5))
            Circle()
                .fill(AppColors.Flow.radarInner)
                .overlay(Circle().strokeBorder(AppColors.Flow.radarInnerStroke, lineWidth: 1.5))
                .frame(width: 84, height: 84)
            Circle()
                .fill(AppColors.Flow.accent)
                .frame(width: 52, height: 52)
            Image(systemName: "figure.run")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            // 旋转的那圈弧线在阶段 4 接（连同「减弱动态效果」的降级）。
            // 现在画成静态的一段弧：**不留空** —— 空着的话匹配态的视觉区只有三个同心圆，
            // 与「正在找人」这件事没有任何视觉关联。
            Circle()
                .trim(from: 0, to: 0.17)
                .stroke(AppColors.Flow.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var avatar: some View {
        matchedAvatarGeometry(
            FlowAvatar(
                name: order.volunteerName,
                diameter: FlowMetrics.avatarDiameter,
                background: AppColors.Flow.avatarBackground,
                foreground: AppColors.Flow.avatarInitial
            )
        )
    }

    /// 倒计时：头像圆**原位**变品牌蓝实心底 + 白色数字，每拍从 1.25 倍回弹到 1 倍。
    ///
    /// 挂同一个 geometry id，所以说「开始」那一刻在动的仍然是这一个圆 —— 它缩到顶行
    /// 变成 ⌀28 的小头像，中间没有任何交叉淡入淡出。
    ///
    /// 🚩 **对读屏隐藏**（整个 `visualArea` 是隐藏的）。数字走 announcement 通道播报，
    /// 不插入遍历顺序、不移动焦点 —— 焦点在这三秒里必须待在原处，
    /// 这正是「原地变形而不是跳页」要保住的东西。
    private func countdownCircle(_ beat: Int) -> some View {
        matchedAvatarGeometry(
            Text("\(beat)")
                .flowFont(FlowFonts.countdownNumber(), monospacedDigit: true)
                .foregroundColor(.white)
                .frame(width: FlowMetrics.avatarDiameter, height: FlowMetrics.avatarDiameter)
                .background(AppColors.Flow.accent, in: Circle())
        )
        // 每拍换一个数字 ⇒ `id` 变 ⇒ 这个视图被换掉一次 ⇒ `transition` 重新播一次回弹。
        // 「减弱动态效果」下换成纯淡入淡出：不缩放、不位移，**但三个数字照样一拍一拍出现**
        // （倒计时是信息不是装饰，见 `transitionAnimation` 的注释）。
        .id(beat)
        .animation(
            reduceMotion ? nil : .spring(response: BlindRunCountdown.bounceResponse, dampingFraction: 0.55),
            value: beat
        )
        .transition(reduceMotion ? .opacity : .scale(scale: BlindRunCountdown.bounceScale).combined(with: .opacity))
    }

    /// 出发态头像外圈那道进度环。
    ///
    /// ⚠️ **进度值是固定的 0.35，不是算出来的。** 没有 ETA 也没有「总距离」这个基准
    /// （后端契约里都没有），任何「按距离算百分比」都要先编一个起始距离。
    /// 画成固定一段是诚实的：它表达「在路上」，不表达「走了多少」。
    /// 阶段 4 接动画时也只做「出现时扫出来」，不做「按进度增长」。
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(AppColors.Flow.radarOuterStroke, lineWidth: FlowMetrics.progressRingWidth)
            Circle()
                .trim(from: 0, to: 0.35)
                .stroke(
                    AppColors.Flow.accent,
                    style: StrokeStyle(lineWidth: FlowMetrics.progressRingWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private var successBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: FlowMetrics.successBadgeDiameter, height: FlowMetrics.successBadgeDiameter)
            .background(AppColors.Flow.successBadge, in: Circle())
            .overlay(
                Circle().strokeBorder(AppColors.Flow.surface, lineWidth: FlowMetrics.successBadgeRingWidth)
            )
            .frame(
                width: FlowMetrics.visualSide,
                height: FlowMetrics.visualSide,
                alignment: .bottomTrailing
            )
            .offset(x: -8, y: -8)
    }

    // MARK: - 信息列表

    private var infoCard: some View {
        FlowCard {
            VStack(spacing: 0) {
                volunteerRow
                FlowSeparator()
                timeRow
                FlowSeparator()
                placeRow
                FlowSeparator()
                lastRow
            }
        }
    }

    /// 陪跑员行：姓名 + 经验，两行值合成一句读屏文本。
    ///
    /// 姓名**视觉上保留掩码**（`张*`）、**朗读去掉星号** —— 后端的姓名始终带掩码，
    /// 原样交给 VoiceOver 会念成「张星号」，而这个 App 的读屏是外放的。
    private var volunteerRow: some View {
        FlowInfoRow(
            label: "陪跑员",
            accessibilityLabel: volunteerAccessibilityLabel,
            minHeight: FlowMetrics.volunteerRowMinHeight
        ) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(volunteerDisplayName)
                    .flowFont(FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
                if let experience = order.volunteerExperienceText {
                    Text(experience)
                        .flowFont(FlowFonts.rowDetail(), monospacedDigit: true)
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !hasVolunteer {
                    Text("匹配成功后显示陪跑经验")
                        .flowFont(FlowFonts.rowDetail())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasVolunteer: Bool { order.volunteerName?.nilIfBlank != nil }

    private var volunteerDisplayName: String {
        guard hasVolunteer else { return "正在匹配" }
        return order.volunteerName ?? ""
    }

    /// ⚠️ 设计稿这里是「张伟，已认证」。**「已认证」不显示** ——
    /// 订单详情里没有这个字段（契约里 0 命中）。无字段却印「已认证」是伪造信任标识，
    /// 而这恰恰是盲人决定要不要把自己交给一个陌生人时唯一能依据的东西。
    /// 已投 handoff 请后端补。
    private var volunteerAccessibilityLabel: String {
        guard hasVolunteer else { return "陪跑员，正在匹配，匹配成功后显示陪跑经验" }
        var label = "陪跑员\(order.volunteerNameForSpeech)"
        if let experience = order.volunteerExperienceText { label += "，\(experience)" }
        return label
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
                onOpenStartPlace: {},
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
