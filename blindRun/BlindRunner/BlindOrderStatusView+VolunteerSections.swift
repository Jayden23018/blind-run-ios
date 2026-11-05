import SwiftUI

extension BlindOrderStatusView {
    @ViewBuilder
    func peerMapSection(_ order: OrderDetailResponse) -> some View {
        if order.status.fetchesVolunteerLocation {
            let peer = viewModel.latestVolunteerSample?.coordinate
            if let peer {
                // 与首页同一条规则：地图是装饰，列表才是界面。它不可交互、不承载任何必要信息
                // ——「志愿者距你多远」的文字版在 `statusHeader` 里，是那一页最大的那个数字。
                // 「同行位置」这个标题一并去掉：视觉扫读才需要标题，这一页没有扫读。
                // 隐藏走 `isDecorative`，不是在外层加 `.accessibilityHidden(true)` ——
                // 后者在真 key 构建下盖不住 `MapViewWrapper` 自己合成的那个元素
                // （2026-08-22 在盲人首页实测，见 `MapViewWrapper.isDecorative` 的说明）。
                // 这一页同样是「地图是装饰、列表才是界面」，所以同一个洞在这里也开着。
                MapViewWrapper(
                    centerCoordinate: peer,
                    showsUserLocation: false,
                    annotations: [MapAnnotationItem(
                        id: "associated-volunteer",
                        coordinate: peer,
                        title: "陪跑员",
                        subtitle: "位置刚刚更新",
                        kind: .peer
                    )],
                    tracksUserLocation: false,
                    isDecorative: true
                )
                .decorativeMapHeight(180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            } else {
                // 但「拿不到位置」必须留在读屏里：盲人据此决定要不要打电话，
                // 这是状态信息不是装饰。
                Text("同行位置暂时不可用")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("同行位置暂时不可用")
            }
        }
    }

    /// 接单后这一页唯一的主动作：打电话给志愿者。
    ///
    /// 此前它是「志愿者信息」卡片里的一行只读文字（`Text("志愿者电话：…")`）。
    /// 打车 App 里视障乘客靠车型 / 车牌 / 颜色确认对方，**陪跑场景这三样都没有** ——
    /// 志愿者是个人，视障者手里唯一的汇合手段就是这通电话。把它做成一行文字，
    /// 等于把唯一的出路藏在第四张卡片里。
    ///
    /// 依据：202 名视障者问卷 + 12 人访谈的结论是导航阶段最优先的信息为「怎么找到正确的那一个」；
    /// Guide Dogs for the Blind 给视障乘客的操作建议直接就是「接驾前几分钟主动打电话说明自己在哪」。
    /// 见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2。
    ///
    /// 只在需要汇合的状态出现：终态（已完成 / 已取消 / 暂无志愿者）下电话可能还在，
    /// 但那时候摆一个占半屏的拨号按钮是错的。
    /// ponytail: 复用 `EmergencyDialer.telURL` —— 它只是在拼 `tel://`，与求助语义无关，
    /// 不值得为「非紧急拨号」再造一个同样的三行函数。
    @ViewBuilder
    func volunteerCallSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersVolunteerCall,
           let volunteerPhone = order.volunteerPhone?.nilIfBlank,
           let telURL = EmergencyDialer.telURL(for: volunteerPhone) {
            Button {
                EmergencyDialer.dial(telURL)
            } label: {
                Text("打电话给陪跑员")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel("打电话给陪跑员")
            // 这里此前是「拨打 \(volunteerPhone)，系统会先弹出拨号确认」——
            // VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，用户还没决定要不要打。
            // 视障跑者在户外常常**不戴耳机**（要听车流），外放等于把志愿者的手机号广播给周围的人。
            // 号码对「要不要打这通电话」这个决策没有任何帮助，唯一有用的信息是「会先弹确认」。
            //
            // 语音拨号那条路**照旧逐位复述号码**（`VoiceStatusQuery.swift:212`），
            // 那不是冗余暴露：用户已经明确说了要打，复述是拨号前确认拨给谁，删掉会变成盲拨。
            .accessibilityHint("系统会先弹出拨号确认，确认后才会拨出")
            .accessibilityIdentifier("blindOrderStatusCallVolunteerButton")
        }
    }

    /// 进通话页的入口。通话本身整个在 `BlindIntroCallView` 里，这里只有一个按钮。
    ///
    /// 🚩 **它不能因为「反正会自动弹」而省掉。** 自动弹出只发生在 `status` **变化**那一跳，
    /// 而用户按过「返回订单」之后本轮就不再自动弹（`BlindIntroCallPresentation`）——
    /// 没有这个按钮，他此刻回不去了：状态卡还在念「有位志愿者想陪你跑，可以打个电话聊聊」，
    /// 而屏幕上没有任何入口。那与 `introCallUnavailable` 当初修的是同一类缺陷。
    ///
    /// 还有一条更细的路会绕过自动弹出：同一次通话磨合里换候选人要经过 `PENDING_MATCH`
    /// （`AGENTS.md` §5），而这一页 5 秒轮一次 —— 后端立刻派给下一位时，那个中间态
    /// 可能整个落在两次轮询之间。客户端看到的是 `PENDING_INTRO_CALL → PENDING_INTRO_CALL`，
    /// `onChange` 不触发。
    ///
    /// 版位与 `volunteerCallSection` / `keepWaitingSection` 相同、状态集互斥
    /// （`.pendingIntroCall` 不在 `offersVolunteerCall` 也不在 `offersKeepWaiting` 里），
    /// 所以读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 🚨 文案**不许复用 `callButtonTitle`**（「打电话给这位志愿者」）：那个按钮按下去
    /// 立刻弹系统拨号确认，这个按钮只是打开一个页面。对看不见屏幕的人，两件事听起来
    /// 一样就等于随时可能误拨。
    @ViewBuilder
    func introCallEntrySection(_ order: OrderDetailResponse) -> some View {
        if order.status == .pendingIntroCall {
            Button {
                introCallPresentation.isShowing = true
            } label: {
                Text(IntroCallCopy.blindEntryButtonTitle)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel(IntroCallCopy.blindEntryButtonTitle)
            .accessibilityHint(IntroCallCopy.blindEntryAccessibilityHint)
            .accessibilityIdentifier("blindOrderStatusIntroCallEntryButton")
        }
    }

    /// 等待期这一页唯一的主动作。
    ///
    /// 后端的 `ORDER_CANCELLATION_WARNING` 正文逐字写着「点击继续等待可延长」，在这个按钮
    /// 存在之前，盲人听到那句话之后**在屏幕上找不到它**，能做的只有等订单被自动取消再重下一单。
    ///
    /// 排在 `volunteerCallSection` 后面同一个版位：两者状态集互斥，等待中给这个、汇合中给电话，
    /// 读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 没有二次确认（幂等 + 方向是保住订单）。取消订单那条的确认对话框不受影响。
    ///
    /// 🚩 **2026-09-05 从 140pt 的实心主按钮降级为 64pt 的描边次级按钮，功能一字未动。**
    /// 等待态这一页真正的主体是「系统正在派单」这条状态，而这个按钮此刻并不是用户**该做**
    /// 的事 —— 它是一条**保险**（不按，订单会在后端的窗口到点后被自动取消）。
    /// 用主按钮的体量把它摆在那里，会让盲人以为等待期有一件必须完成的操作。
    ///
    /// 🚨 **降级的是体量，不是可达性。** 三条不许动：
    /// 1. 仍在 `statusHeader` 之后的同一个版位，读屏遍历顺序不变；
    /// 2. 仍是整行铺满、64pt 高（`docs/research/blind-ui-visual-benchmark-20260808.md`
    ///    那条「次级操作一律整行铺满竖直堆叠」，与「换一位」「取消订单」同档）；
    /// 3. `repeatStatus` 里那句 `KeepWaitingCopy.repeatStatusSuffix` 照旧念 ——
    ///    看不见屏幕的人靠它知道这个按钮存在，那才是它真正的发现路径。
    ///
    /// `buttonShapeOutlineIfNeeded` 不能省：这一段降级后是纯文字按钮，开启「按钮形状」
    /// 的低视力用户否则看不出它可点（与 `actionSection` 的「取消订单」同一条理由）。
    @ViewBuilder
    func keepWaitingSection(_ order: OrderDetailResponse) -> some View {
        if viewModel.canShowKeepWaiting {
            Button {
                Task { await viewModel.keepWaiting() }
            } label: {
                Text(KeepWaitingCopy.buttonTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .disabled(viewModel.isPerformingAction)
            .buttonShapeOutlineIfNeeded(color: AppColors.primary)
            .accessibilityLabel(KeepWaitingCopy.buttonTitle)
            .accessibilityHint(KeepWaitingCopy.accessibilityHint)
            .accessibilityIdentifier("blindOrderStatusKeepWaitingButton")
        }
    }
}
