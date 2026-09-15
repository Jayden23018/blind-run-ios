import SwiftUI

// MARK: - 陪跑进行中（IN_PROGRESS）的执行屏

/// 产品定稿 2026-09-15：**Active Run 是执行屏，不是仪表盘。**
///
/// 跑动中这一屏只留四样东西 —— 状态与搭档 / 连接状态 / 距离 / 时长与配速，
/// 加上永远贴在最底下的求助。版式规格见
/// `docs/research/blind-runner-ui-reference-study-20260915.md` §27 / §27.1 / §28。
///
/// 🚩 **它替换的是 `BlindOrderStatusView` 在 `IN_PROGRESS` 时的整个内容区**，不是插在里面。
/// 那一屏原本渲染 6 组内容（状态卡 / 打电话给志愿者 140pt / 问一句 / 把行程告诉家人 /
/// 装饰地图 / 两个折叠组）。它们**没有被删**，只是不在这一态出现：
///
/// | 原来在这屏的 | 现在在哪 | 为什么不必改判定 |
/// |---|---|---|
/// | 打电话给志愿者 | 求助中心第一项（`BlindActiveRunSafetyHubOption.contactVolunteer`） | 语音「打电话给志愿者」那条路照旧（`VoiceStatusQuery.callAnswer` 读的是 `offersVolunteerCall`，没动） |
/// | 问一句 | 本屏底部安静文字按钮 | 同一个 `viewModel.askVoiceQuestion()` |
/// | 把行程告诉家人 | 出发前那几态（`offersRunPlanShare` 覆盖 `PENDING_MATCH` → `DRIVER_ARRIVED`） | 判定一行没改，只是 `IN_PROGRESS` 走了这条新分支 |
/// | 装饰地图 | 去掉。位置改成「播报我的位置」按需播 | 读屏念不出地图，低视力用户在跑动中也看不清 |
/// | 预约信息 / 状态变更记录 | 其余所有状态的订单页仍在原处 | 同上 |
///
/// 判定一个都没改，是这次改动最省的地方：`offersVolunteerCall` / `offersRunPlanShare` 这些
/// 穷举 switch 动一下就会牵连语音、志愿者端和一批用例，而这里要的只是「这一态换个内容区」。
struct BlindActiveRunView: View {
    let order: OrderDetailResponse
    let stats: TrackStats?
    let isLocationFresh: Bool

    /// 主数字。70pt 是**未缩放**的基准，随 Dynamic Type 走 —— 写死 `size:` 会让整屏在 AX 档下纹丝不动。
    @ScaledMetric(relativeTo: .largeTitle) private var primaryNumberSize: CGFloat = 70
    @ScaledMetric(relativeTo: .title) private var secondaryNumberSize: CGFloat = 32

    var body: some View {
        // 🚩 AX5 档下四组内容会不会顶掉留白甚至溢出，是本设计已知的风险点（§27.1 末尾）。
        //
        // `ViewThatFits` 恰好能判它：`Spacer()` 的 ideal 高度是 0，所以第一个候选的 ideal 高度
        // 就是**纯文字堆起来的高度**。文字本身还装得下 → 选它，`Spacer()` 把余量平分（正常字号
        // 下的均匀分布）；文字已经装不下 → 落到第二个候选，改成可滚动 + 固定间距。
        // 宁可滚动也不裁切：裁掉的是这一屏仅有的三个数字。
        ViewThatFits(in: .vertical) {
            metricsColumn(usesFlexibleSpacing: true)
            ScrollView { metricsColumn(usesFlexibleSpacing: false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.activeRunSurface)
    }

    @ViewBuilder
    private func metricsColumn(usesFlexibleSpacing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            groupGap(usesFlexibleSpacing)
            metric(
                value: stats?.distanceKilometersText,
                label: "总距离（公里）",
                spokenValue: stats?.distanceText,
                spokenLabel: "总距离",
                size: primaryNumberSize
            )
            groupGap(usesFlexibleSpacing)
            HStack(alignment: .top, spacing: 0) {
                metric(
                    value: stats?.durationClockText,
                    label: "总时长",
                    spokenValue: stats?.durationText,
                    spokenLabel: "总时长",
                    size: secondaryNumberSize
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                metric(
                    value: stats?.paceClockText,
                    label: "实时配速",
                    spokenValue: stats?.averagePaceText,
                    spokenLabel: "实时配速",
                    size: secondaryNumberSize
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            groupGap(usesFlexibleSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 左右 24pt。第一版 18pt 被产品方判为太紧（§27.1）。
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .readableContentColumn()
    }

    /// 组与组之间的留白。**组内紧（数字贴标签 6pt）、组间松** —— 拉不开这个对比整屏就会「哪都挤」。
    @ViewBuilder
    private func groupGap(_ usesFlexibleSpacing: Bool) -> some View {
        if usesFlexibleSpacing {
            // 自适应平分，不写死：写死的间距在 iPhone SE 上会挤、Pro Max 上会散（§27.1）。
            Spacer(minLength: 24)
        } else {
            // AX 档的退路。这时留白已经不是问题了，能把三个数字完整读出来才是。
            Spacer().frame(height: 28)
        }
    }

    /// 顶行：`陪跑中 · 张伟` + `● 定位正常`。合成**一个**焦点里的两条，
    /// 但两条各自是独立的无障碍元素 —— 产品定的遍历顺序第 1、2 位就是它们俩。
    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(partnerHeadline)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .accessibilityLabel(partnerHeadline)

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                // 圆点是纯装饰：「几格信号」这种纯视觉编码读屏念不出来，所以状态由**文字**承担
                // （§28.4）。圆点只是给看得见的人一个扫读锚点。
                Circle()
                    .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(locationStatusText)
                    .font(.caption)
                    .foregroundColor(AppColors.activeRunSecondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(locationStatusText)
        }
    }

    private var partnerHeadline: String {
        "\(order.status.displayName) · \(order.volunteerName?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName)"
    }

    /// 🚩 判的是**本机定位新不新鲜**，不是后端的 `ESCORT_SIGNAL_LOST`。
    /// 那条事件是一次性告警（`AppRealtimeCoordinator.routeEscortAlert`），没有可以持续读的状态；
    /// 而用户看到这一行能做的事（换个开阔地方、检查权限）恰恰只跟本机定位有关。
    ///
    /// 措辞是「信号弱」不是「定位失败」：权限正常但在室内 / 高楼间拿不到定位是常态，
    /// 说成失败会把人支去翻设置解决一个不存在的问题（同 `locationUnavailable` 的分岔理由）。
    private var locationStatusText: String {
        isLocationFresh ? "定位正常" : "定位信号弱"
    }

    /// 一个数字 + 它的标签。**两者之间 6pt** —— 标签必须贴着它解释的那个数字（§27.1）。
    ///
    /// 屏幕上用跑表体例（`2.41` / `01:54` / `9'06"`），读屏念的是口语体例
    /// （`2.41 公里` / `1 分 54 秒` / `9 分 6 秒每公里`）。两套**不是重复**：
    /// `9'06"` 读屏会念成「九撇零六引号」。
    private func metric(
        value: String?,
        label: String,
        spokenValue: String?,
        spokenLabel: String,
        size: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value ?? "--")
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                // 数字变宽会让整行跳动；`minimumScaleFactor` 只在 AX 档下兜一次，
                // 不用它顶替 `ViewThatFits`（缩到看不清不是解法）。
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.activeRunSecondaryText)
        }
        .accessibilityElement(children: .combine)
        // 拿不到数据时**说清是在获取，不念「杠杠」**。这一态的空态在契约里就是
        // 「本次路线仍在采集，暂时没有足够的轨迹点」（`OrderTrackResponse.emptyStateText`），
        // 不是错误 —— 刚起跑的头十几秒本来就没有足够的轨迹点。
        .accessibilityLabel(spokenValue.map { "\(spokenLabel) \($0)" } ?? "\(spokenLabel)，正在获取")
    }
}

// MARK: - 底部安全锚点

/// 贴在陪跑中那屏最底下的一整块。**位置固定，不随内容浮动** ——
/// 盲人靠的是「屏幕最下面那一块」这个物理位置记忆，会浮动的安全入口等于没有位置记忆。
///
/// 上面那一行两个安静的文字按钮是刻意的低视觉权重：产品要求「重复当前状态」
/// 「remain available as an accessibility function」但**不与主信息竞争视觉**。
///
/// 🚩 **没有做成纯 `accessibilityAction`。** 那样只有开读屏的人够得着，而
/// `VisionLevel.LOW_VISION` 在数据模型里是一等公民 —— 不开读屏、把字调到 AX5 的低视力用户
/// 会因此永久失去这两个功能（记忆 `low-vision-visual-channel-unaudited` 记的就是这条通道被漏掉）。
/// 代价是 VoiceOver 遍历从产品期望的 6 站变成 8 站，求助仍然是最后一站。
struct BlindActiveRunSafetyAnchor: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let onRepeatStatus: () -> Void
    let onOpenSafetyHub: () -> Void
    /// 长按 3 秒 / 自定义无障碍动作：**跳过二次确认**，直接进倒计时。
    /// 轻点走 `onOpenSafetyHub`，云端求助在那一层里仍然要确认。
    let onTriggerEmergencyImmediately: () -> Void
    /// 本人撤销自己刚发出的求助（`PUT /api/emergency/{id}/cancel`）。
    /// **撤销权只在受助者本人和客服手里**（`AGENTS.md` §6），所以这个入口在盲人端不能没有。
    let onCancelOwnEmergency: () -> Void
    /// 云端求助失败后的一跳拨号兜底。
    ///
    /// 🔴 **不能让用户再走一遍「求助 → 菜单 → 拨号」**。最坏路径是等定位 5 秒 + 请求超时 15 秒，
    /// 按下到听见「未发出」最长 20 秒；在那之后多插一层菜单，是这个仓库能自己消掉的
    /// 最贵一段延迟（理由原文见被删掉的 `EmergencyActionSection`，判断没变，只是换了位置）。
    let onLocalCall: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 「问一句」2026-09-15 搬进求助中心（`BlindSafetyHubView` 的第三格）——
            // 它是产品说的那五个跑中求助功能之一，而这一屏的定稿是「底部只留一个入口」。
            // **它没有被做成纯 `accessibilityAction`**：那样只有开读屏的人够得着，
            // 而低视力用户在弹层里仍然看得见摸得到那一格（记忆 `low-vision-visual-channel-unaudited`）。
            //
            // 「重复当前状态」留在这里：它不是求助功能，而是系统 Speak Screen 读不到
            // 一次性 announcement 时唯一的补救，产品要求它常驻可见。
            quietButton("重复当前状态", hint: "点击后重新播报当前状态和已跑里程", action: onRepeatStatus)
                .padding(.horizontal, 24)
                .readableContentColumn()
                .accessibilityIdentifier("blindActiveRunRepeatStatusButton")

            // 云端求助的进行时 / 失败文案。只有云端那条链路会产生状态，拨号不会。
            if let message = coordinator.state.message {
                EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .readableContentColumn()
            }

            // 求助没发出去时屏幕上必须有一个**能按的东西**，而不只是一段说明。
            // 判据直接读 `state.isFailure`，新增失败态自动进来。
            if coordinator.state.isFailure {
                quietButton(
                    EmergencySafetyCopy.homeCallTitle,
                    hint: EmergencySafetyCopy.cloudFailedCallAccessibilityHint,
                    action: onLocalCall
                )
                .padding(.horizontal, 24)
                .readableContentColumn()
                .accessibilityIdentifier("blindActiveRunFailureCallButton")
            }

            // 只有本人发出、且还没结束的求助才谈得上撤销。
            if coordinator.activeEvent != nil {
                quietButton(
                    EmergencySafetyCopy.cancelButtonTitleForOwner,
                    hint: "误触时撤销本次求助，需要确认",
                    action: onCancelOwnEmergency
                )
                .padding(.horizontal, 24)
                .readableContentColumn()
                .accessibilityIdentifier("blindActiveRunCancelEmergencyButton")
            }

            safetyHubBlock
        }
        .background(AppColors.activeRunSurface)
        .accessibilityIdentifier("blindActiveRunSafetyAnchor")
    }

    /// 贴边全宽、**零圆角零边距**。不复用 `PrimaryButton`：那个是 12pt 圆角 + 内容列宽度的按钮，
    /// 而这一块的形状本身就是它的可寻址性 —— 拇指从屏幕下缘往上摸，摸到哪都是它。
    ///
    /// 🚩 **轻点与长按后果不同**：轻点打开求助中心（云端求助在那一层里仍要二次确认），
    /// 长按 3 秒**跳过二次确认**直接进倒计时。副标题那行小字是长按这条路径唯一的告知途径，
    /// 不能删 —— 不知道能长按的人不会误触，不知道长按会跳过确认的人才会。
    ///
    /// 形状/高度/配色一个字节没动（2026-09-15 定稿）：拇指盲摸靠的是这块的物理边界，
    /// 而 `activeRunDestructive` 是为深灰底算过对比度的，换成设计稿上的黑胶囊会让边界糊掉。
    private var safetyHubBlock: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .accessibilityHidden(true)
                Text(EmergencySafetyCopy.hubTitle)
                    .font(.system(size: 31, weight: .bold))
            }
            Text(EmergencySafetyCopy.hubEntrySubtitle)
                .font(AppFonts.caption().weight(.semibold))
                .opacity(0.9)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        // **不是 `AppColors.destructive`。** 那个跟随系统外观，而这一屏的底色是固定深灰 ——
        // 亮色档的深红压上去只有 2.96:1，块的边界会糊掉。详见 `activeRunDestructive`。
        .background(AppColors.activeRunDestructive)
        .contentShape(Rectangle())
        // 不用 `Button`：`Button` 把长按当成「取消这次点击」吃掉，两个手势挂在同一个
        // `Button` 上时长按那条永远拿不到（同 `EmergencySOSLongPressButton`）。
        .onLongPressGesture(minimumDuration: SafetyLongPress.duration) {
            guard !coordinator.state.isBusy else { return }
            onTriggerEmergencyImmediately()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                guard !coordinator.state.isBusy else { return }
                onOpenSafetyHub()
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(EmergencySafetyCopy.hubAccessibilityLabel)
        .accessibilityHint(EmergencySafetyCopy.hubAccessibilityHint)
        // 读屏用户不必去猜「双击并按住」按不按得住 —— 上下轻扫选这个动作即可。
        // 它按长按算（跳过二次确认），理由见 `emergencyAccessibilityActionName`。
        .accessibilityAction(named: Text(EmergencySafetyCopy.emergencyAccessibilityActionName)) {
            guard !coordinator.state.isBusy else { return }
            onTriggerEmergencyImmediately()
        }
        .accessibilityIdentifier("blindActiveRunSafetyHubButton")
    }

    private func quietButton(
        _ title: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.activeRunSecondaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .buttonShapeOutlineIfNeeded(color: AppColors.activeRunSecondaryText)
            .accessibilityLabel(title)
            .accessibilityHint(hint)
    }
}
