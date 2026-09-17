import SwiftUI

// MARK: - 邀请卡（设计交付文档 v3 §4.4.2 / §4.4.3）

/// 派单来了之后那张**底部卡**。替代了此前那个居中的全屏模态 `VolunteerDispatchOverlay`。
///
/// 🚩 **内容全部由 `VolunteerOrderFlowPresentation.make(dispatch:)` 或它用的同一批
/// 格式化函数算出来**，与「查看详情」那一页共用一份口径。抄第二份的表现是
/// 「卡片说明天 7:00、详情页说 9月18日 07:00」—— 那是 `RunPlanFormat.shortStart`
/// 注释里逐字记着的坑。
///
/// 🚩 **这一层不画四步进度条。** 它是一次打断：30 秒窗口内要让人一眼看完并决定；
/// 完整订单页是给「我想再看看」的人的第二跳。
struct VolunteerInviteSheet: View {
    @ObservedObject var viewModel: VolunteerHomeViewModel
    let onRespond: (Int64, OrderRespondAction) -> Void
    let onDecline: (Int64) -> Void

    /// 打开时焦点落在标题行（§4.4.2「读屏：打开时焦点在标题行」）。
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            // 一张卡一页。`selection` 绑 orderId 而不是下标 —— 队列会在翻页期间增删
            // （新邀请进来、旧邀请过期），下标会指到另一个人身上，而这一屏的动作是替他回复。
            TabView(selection: currentIDBinding) {
                ForEach(viewModel.invites) { invite in
                    ScrollView {
                        VolunteerInviteCard(
                            invite: invite,
                            isResponding: viewModel.isRespondingToDispatch,
                            onAccept: { onRespond(invite.id, invite.order.dispatchRespondAction) },
                            onDecline: { onDecline(invite.id) },
                            onOpenOrder: { viewModel.openAcceptedOrder(orderID: invite.id) },
                            onDismiss: { viewModel.dismissInvite(orderID: invite.id) }
                        )
                        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
                        .padding(.bottom, 24)
                    }
                    .tag(Optional(invite.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(AppColors.Flow.page)
        .onAppear { titleFocused = true }
        // 队列翻到下一张时把焦点带过去。没有这一行的表现是：回复完一条之后卡片换了，
        // 而读屏焦点还停在已经不存在的那张卡上 —— VoiceOver 会跳回屏幕顶端从头念。
        .onChange(of: viewModel.currentInviteID) { _ in titleFocused = true }
    }

    private var currentIDBinding: Binding<Int64?> {
        Binding(
            get: { viewModel.currentInviteID ?? viewModel.invites.first?.id },
            set: { viewModel.currentInviteID = $0 }
        )
    }

    // MARK: 标题行 + 进度条

    @ViewBuilder
    private var header: some View {
        let invite = viewModel.currentInvite
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(VolunteerInviteCopy.sheetTitle(count: viewModel.invites.count))
                    .flowFont(FlowFonts.homeCardRowTitle())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)

                if viewModel.invites.count > 1 {
                    pageDots
                }

                Spacer(minLength: 0)

                if let invite, invite.isAwaitingReply {
                    Text(VolunteerOrderFlowCopy.replyCountdown(seconds: invite.remainingSeconds))
                        .flowFont(
                            invite.isUrgent ? FlowFonts.rowValueEmphasized() : FlowFonts.rowLabel(),
                            monospacedDigit: true
                        )
                        .foregroundColor(
                            invite.isUrgent ? AppColors.Flow.replyUrgentText : AppColors.Flow.secondaryText
                        )
                }
            }

            if let invite, invite.isAwaitingReply {
                replyProgress(invite)
            }
        }
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 14)
        // 多张卡时给读屏一条**确定**能用的翻页路径。`TabView(.page)` 本身要三指滑动，
        // 而这个动作在 VoiceOver 新手里几乎没人知道。
        //
        // ⚠️ 用例只能断言这两个动作**存在**（无障碍树的形状）：`XCUIElement.tap()` 注入的是
        // 物理触摸，走不到 accessibility action —— 见记忆 `xcuitest-cannot-invoke-accessibility-actions`。
        // 行为那一半由 `VolunteerInviteQueue` 的单测直接调 view model 验。
        .accessibilityAction(named: "下一个邀请") { step(by: 1) }
        .accessibilityAction(named: "上一个邀请") { step(by: -1) }
    }

    /// 分页点。**纯装饰** —— 「第几个 / 共几个」已经在标题行的「N 个新邀请」里说过了，
    /// 再念一遍六个圆点是纯噪音。
    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(viewModel.invites) { invite in
                Circle()
                    .fill(
                        invite.id == viewModel.currentInvite?.id
                            ? AppColors.Flow.accent
                            : AppColors.Flow.progressTrack
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    /// 回复进度条（§4.4.2 第 3 项，3pt，剩余时间占比）。
    ///
    /// **对读屏隐藏**：它和上面那行「还剩 X 秒回复」说的是同一件事，而那行是文字。
    /// 取值 ≥3:1 的理由与断言在 `FlowDesignSystemTests` 里 ——
    /// 设计稿给的 `#D99A00` 压这条底只有 1.96，照抄等于让它在低视力眼里消失。
    private func replyProgress(_ invite: VolunteerInviteState) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.Flow.progressTrack)
                Capsule()
                    .fill(invite.isUrgent ? AppColors.Flow.replyProgressUrgent : AppColors.Flow.accent)
                    .frame(width: geometry.size.width * invite.remainingFraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private func step(by offset: Int) {
        guard let current = viewModel.currentInvite?.id,
              let index = viewModel.invites.firstIndex(where: { $0.id == current }) else { return }
        let next = index + offset
        guard viewModel.invites.indices.contains(next) else { return }
        viewModel.currentInviteID = viewModel.invites[next].id
    }
}

// MARK: - 一张卡

/// 单张邀请卡。三种形态在**同一张卡上原地切换**（§4.4.3「不关闭再弹新弹层」）：
/// 待回复 / 已约好 / 已失效。
///
/// 🚩 **「被别人接」那一种不做。** 它只在从「附近还没人接的」列表进入时才可能发生，
/// 而那条链路当前是关的（`MockAPIClient.swift` 里被刻意删掉，后端
/// `GET /api/orders/available` 也没有「等了多久」这个维度）。
/// 定向派单的失败只有一种：过期。
struct VolunteerInviteCard: View {
    let invite: VolunteerInviteState
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onOpenOrder: () -> Void
    let onDismiss: () -> Void

    @State private var showsDetail = false

    private var presentation: VolunteerOrderFlowPresentation {
        .make(dispatch: invite.order, remainingSeconds: invite.remainingSeconds)
    }

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: 16) {
                switch invite.outcome {
                case .none:
                    awaitingContent
                case .accepted:
                    acceptedContent
                case .expired:
                    expiredContent
                }
            }
            .padding(FlowMetrics.homeCardPadding)
        }
        .fullScreenCover(isPresented: $showsDetail) { detailPage }
    }

    // MARK: 待回复

    @ViewBuilder
    private var awaitingContent: some View {
        Text(presentation.title)
            .flowFont(FlowFonts.inviteTime())
            .foregroundColor(AppColors.Flow.primaryText)
            .fixedSize(horizontal: false, vertical: true)

        if let meetingPoint = invite.order.startAddress?.nilIfBlank {
            Text(meetingPoint)
                .flowFont(FlowFonts.homeCardPlace())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        metrics

        // 🔴 设计稿这里还有一行「李先生 / 全盲，用引导绳」和一条「赶路时间不足」的浅黄提示条。
        // **两条都不渲染，不是漏了：**
        // ① 跑者姓名 / 视力 / 引导方式：`NEW_ORDER` 推送里没有这三项（已投 handoff）。
        //    给还没见面的陪跑员印一个猜的视力程度，见面第一下就会抓错人。
        // ② 「赶过来约 25 分钟」要路程估算，本 App 不做路线导航；而真正能预测「接下会失败」
        //    的判据是后端配置 `app.order.booking-buffer-minutes`（当前 60 分钟，接单那一刻
        //    冲突直接回 `VOLUNTEER_ALREADY_ENGAGED`），客户端拿不到。照设计稿写 30 分钟
        //    会让 30–60 分钟那一档连提示都没有就撞 409。已投 handoff。

        FlowActionButton(
            VolunteerOrderFlowCopy.acceptInvite,
            isLoading: isResponding,
            isEnabled: !isResponding,
            accessibilityHint: acceptHint,
            action: onAccept
        )
        .accessibilityIdentifier(
            invite.order.dispatchRespondAction == .interested
                ? "volunteerDispatchInterestedButton"
                : "volunteerDispatchAcceptButton"
        )

        HStack {
            Button(VolunteerOrderFlowCopy.declineInvite) { onDecline() }
                .accessibilityHint("直接回复去不了，不问原因、不计任何记录。5 秒内可以撤销")
                .accessibilityIdentifier("volunteerInviteDeclineButton")

            Spacer(minLength: 0)

            Button(VolunteerInviteCopy.detail) { showsDetail = true }
                .accessibilityHint("打开完整的陪跑订单页，倒计时继续走")
                .accessibilityIdentifier("volunteerDispatchDetailButton")
        }
        .flowFont(FlowFonts.rowValue())
        .foregroundColor(AppColors.Flow.accent)
        .frame(minHeight: 44)
        .disabled(isResponding)
    }

    /// 「先聊聊」那一支要说清**还不是接单**：把 `INTERESTED` 当成接单的人会以为事情定了，
    /// 然后错过跑者那通电话 —— 而 20 分钟窗口过了这一单就换人了。
    ///
    /// 按钮**文字**两种情况相同（设计交付 v3 §5：主按钮就叫「接下这次陪跑」）：
    /// 陪跑员要做的决定是同一个，「先聊聊还是直接接」是后端的机制，不该变成两个按钮。
    private var acceptHint: String {
        invite.order.dispatchRespondAction == .interested
            ? "先锁定这一单并等跑者打电话给你，聊完双方都说合适才算接单"
            : "接下这一单并进入服务流程"
    }

    /// 三格数据（§4.4.2 第 6 项）。**缺哪格就不画哪格**，不摆「--」——
    /// 用户没填时后端整个键不出现，写「未填写」是把「不知道」显示成一个值。
    @ViewBuilder
    private var metrics: some View {
        let tiles: [(String, String)] = [
            invite.order.distanceKm.map {
                (VolunteerInviteCopy.distanceToStartLabel, String(format: "%.1f 公里", $0))
            },
            invite.order.plannedDistanceText.map { (VolunteerOrderFlowCopy.plannedDistanceLabel, $0) },
            invite.order.plannedPaceText.map { (VolunteerOrderFlowCopy.paceLabel, $0) }
        ].compactMap { $0 }

        if !tiles.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                    if index > 0 {
                        Rectangle()
                            .fill(AppColors.Flow.separator)
                            .frame(width: 1, height: 30)
                            .accessibilityHidden(true)
                    }
                    VStack(spacing: 4) {
                        Text(tile.1)
                            .flowFont(FlowFonts.rowValueEmphasized())
                            .foregroundColor(AppColors.Flow.primaryText)
                        Text(tile.0)
                            .flowFont(FlowFonts.rowDetail())
                            .foregroundColor(AppColors.Flow.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    // 读屏念「离你，3.2 公里」而不是屏幕上的「3.2 公里 / 离你」——
                    // 屏幕上值在上是为了扫读，念出来必须先说这是什么。
                    .accessibilityLabel("\(tile.0)，\(tile.1)")
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColors.Flow.bookingBackground)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        }
    }

    // MARK: 已约好（§4.4.3「接下成功」）

    @ViewBuilder
    private var acceptedContent: some View {
        outcomeBadge(systemImage: "checkmark", tint: AppColors.Flow.successBadge)

        Text(VolunteerInviteCopy.acceptedTitle)
            .flowFont(FlowFonts.bookingTitle())
            .foregroundColor(AppColors.Flow.primaryText)
            .accessibilityAddTraits(.isHeader)

        Text(acceptedDetailLine)
            .flowFont(FlowFonts.statusSubtitle())
            .foregroundColor(AppColors.Flow.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        // 设计稿原话是「李明的全名和电话已放进订单」。**名字这一刻拿不到**
        //（`NEW_ORDER` 没有 `blindName`），换成「跑者」而不是留一个空位。
        Text(VolunteerInviteCopy.acceptedDetail)
            .flowFont(FlowFonts.statusSubtitle())
            .foregroundColor(AppColors.Flow.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        FlowActionButton(VolunteerInviteCopy.acceptedPrimary, action: onOpenOrder)
            .accessibilityIdentifier("volunteerInviteOpenOrderButton")

        Button(VolunteerInviteCopy.acceptedSecondary) { onDismiss() }
            .flowFont(FlowFonts.rowValue())
            .foregroundColor(AppColors.Flow.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("volunteerInviteBackToDispatchButton")
    }

    private var acceptedDetailLine: String {
        [presentation.title, invite.order.startAddress?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "　")
    }

    // MARK: 已失效（§4.4.3「已过期」与「在卡片打开期间过期」是同一张卡）

    @ViewBuilder
    private var expiredContent: some View {
        outcomeBadge(systemImage: "clock", tint: AppColors.Flow.secondaryText)

        Text(VolunteerInviteCopy.expiredTitle)
            .flowFont(FlowFonts.bookingTitle())
            .foregroundColor(AppColors.Flow.secondaryText)
            .accessibilityAddTraits(.isHeader)

        Text(VolunteerInviteCopy.expiredDetail)
            .flowFont(FlowFonts.statusSubtitle())
            .foregroundColor(AppColors.Flow.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        FlowActionButton(VolunteerInviteCopy.expiredPrimary, action: onDismiss)
            .accessibilityIdentifier("volunteerInviteExpiredAcknowledgeButton")
    }

    /// 结果态那枚圆形图标。**对读屏隐藏** —— 紧跟着的标题已经把结果说清楚了。
    /// 靠**形状**区分成功与失效（对勾 / 时钟），不只靠颜色（WCAG 1.4.1）。
    private func outcomeBadge(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 64, height: 64)
            .background(tint, in: Circle())
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: 查看详情

    /// 完整的「邀请」订单页。与「约好」「出发」同一个骨架，进度条第 1 步高亮。
    ///
    /// 倒计时照常走：这一层是**同一次派单的另一种看法**，不是一个可以慢慢看的副本。
    private var detailPage: some View {
        NavigationStack {
            VolunteerOrderFlowPage(
                presentation: presentation,
                // 派单载荷里没有跑者姓名（`AGENTS.md` §8：接单前只给取值空间封闭的字段），
                // 所以头像圆里是「跑」。**不编一个名字**。已投 handoff 请后端补掩码姓名。
                runnerName: nil,
                onRowAction: { action in
                    guard case .declineInvite = action else { return }
                    showsDetail = false
                    onDecline()
                },
                onPrimaryAction: {
                    showsDetail = false
                    onAccept()
                },
                isPrimaryLoading: isResponding,
                isPrimaryEnabled: !isResponding,
                footer: { EmptyView() }
            )
            .navigationTitle(VolunteerOrderFlowCopy.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { showsDetail = false }
                        .accessibilityHint("回到邀请卡，倒计时没有停")
                }
            }
        }
    }
}

// MARK: - 「这次去不了」的撤销 toast（§4.4.3）

/// 底部那条 5 秒可撤销的提示。
///
/// 🔴 **撤销之所以能实现，是因为请求还没发出去。** 后端 `POST /{id}/respond` 只有三个
/// action，`handleDecline` 一进去就把这一单推给下一个人，**没有撤销入口** ——
/// 先发再撤是撤不回来的（见 `VolunteerHomeViewModel.declineInvite`）。
struct VolunteerDeclineUndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(VolunteerInviteCopy.declineToastText)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(.white)

            Spacer(minLength: 0)

            Button(VolunteerInviteCopy.declineToastUndo, action: onUndo)
                .flowFont(FlowFonts.rowValueEmphasized())
                .foregroundColor(AppColors.Flow.cta)
                // 撤销是这条 toast 存在的**唯一**理由，而它只活 5 秒 ——
                // 64pt 触达区在这里不是体例，是「点不中就真的拒绝了」。
                .frame(minWidth: 64, minHeight: 44)
                .accessibilityHint("取消这次「去不了」，把邀请放回来")
                .accessibilityIdentifier("volunteerDeclineUndoButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.Flow.navy)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .accessibilityElement(children: .contain)
    }
}
